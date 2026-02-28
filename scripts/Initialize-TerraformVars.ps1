<#
.SYNOPSIS
    Interactively populates terraform/terraform.tfvars for the W365Claw project.

.DESCRIPTION
    Auto-detects latest software versions, SHA256 checksums, Azure subscription,
    and source image versions. Prompts for all values with sensible defaults.
    Parses existing terraform.tfvars for idempotent re-runs.

    Works in both Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER Force
    Skip confirmation prompts; use detected/existing defaults for all values.

.PARAMETER TerraformDir
    Path to the terraform/ directory. Defaults to ..\terraform relative to this script.

.EXAMPLE
    .\Initialize-TerraformVars.ps1
    # Interactive mode

.EXAMPLE
    .\Initialize-TerraformVars.ps1 -Force
    # Non-interactive — auto-detect everything and write immediately
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [string]$TerraformDir = (Join-Path $PSScriptRoot "..\terraform")
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ═══════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "─── $Message ───" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor DarkGray
}

function Write-Success {
    param([string]$Message)
    Write-Host "  ✅ $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  ⚠️  $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "  ❌ $Message" -ForegroundColor Red
}

function Test-CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Read-ValueWithDefault {
    <#
    .SYNOPSIS
        Prompts user for a value, showing current default. Returns default if empty input or -Force.
    #>
    param(
        [string]$Prompt,
        [string]$Default,
        [string]$ValidationRegex,
        [string]$ValidationMessage
    )

    if ($Force) { return $Default }

    while ($true) {
        $display = if ($Default) { "[$Default]" } else { "[empty]" }
        $input_val = Read-Host "  $Prompt $display"
        if ([string]::IsNullOrWhiteSpace($input_val)) { $input_val = $Default }

        if ($ValidationRegex -and $input_val) {
            if ($input_val -notmatch $ValidationRegex) {
                Write-Err $ValidationMessage
                continue
            }
        }
        return $input_val
    }
}

function Read-BoolWithDefault {
    param([string]$Prompt, [string]$Default)

    if ($Force) { return $Default }

    while ($true) {
        $input_val = Read-Host "  $Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($input_val)) { return $Default }
        if ($input_val -eq "true" -or $input_val -eq "false") { return $input_val }
        Write-Err "Must be 'true' or 'false'"
    }
}

function Read-IntWithDefault {
    param([string]$Prompt, [string]$Default)

    if ($Force) { return $Default }

    while ($true) {
        $input_val = Read-Host "  $Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($input_val)) { return $Default }
        $parsed = 0
        if ([int]::TryParse($input_val, [ref]$parsed)) { return $input_val }
        Write-Err "Must be an integer"
    }
}

function Invoke-WebRequestSafe {
    <#
    .SYNOPSIS
        Wrapper for Invoke-WebRequest that returns $null on failure instead of throwing.
    #>
    param([string]$Uri)
    try {
        $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 15
        return $response
    } catch {
        Write-Info "Could not fetch $Uri — $($_.Exception.Message)"
        return $null
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# PARSE EXISTING TFVARS
# ═══════════════════════════════════════════════════════════════════════════

function Read-TfVars {
    <#
    .SYNOPSIS
        Parses an existing terraform.tfvars file into a hashtable.
        Handles quoted strings, booleans, integers, and the tags = { ... } map block.
    #>
    param([string]$Path)

    $vars = @{}
    if (-not (Test-Path $Path)) { return $vars }

    $content = Get-Content $Path -Raw
    $lines = $content -split "`n"

    $inMap = $false
    $mapName = ""
    $mapValues = @{}

    foreach ($line in $lines) {
        $trimmed = $line.Trim()

        # Skip comments and empty lines
        if ($trimmed -eq "" -or $trimmed.StartsWith("#")) { continue }

        # Detect map block start: key = {
        if (-not $inMap -and $trimmed -match '^(\w+)\s*=\s*\{') {
            $inMap = $true
            $mapName = $Matches[1]
            $mapValues = @{}
            continue
        }

        # Inside map block
        if ($inMap) {
            if ($trimmed -eq "}") {
                $vars[$mapName] = $mapValues
                $inMap = $false
                $mapName = ""
                continue
            }
            # Parse map entries: key = "value"
            if ($trimmed -match '^(\w+)\s*=\s*"([^"]*)"') {
                $mapValues[$Matches[1]] = $Matches[2]
            }
            continue
        }

        # Simple key = value
        if ($trimmed -match '^(\w+)\s*=\s*(.+)$') {
            $key = $Matches[1]
            $val = $Matches[2].Trim()

            # Strip inline comments
            # Handle quoted strings first
            if ($val.StartsWith('"')) {
                if ($val -match '^"([^"]*)"') {
                    $val = $Matches[1]
                }
            } else {
                # Unquoted — could be bool, int, or unquoted string
                # Strip inline comment
                $commentIdx = $val.IndexOf("#")
                if ($commentIdx -ge 0) { $val = $val.Substring(0, $commentIdx).Trim() }

                # Don't transform — keep as string
            }
            $vars[$key] = $val
        }
    }

    return $vars
}

# ═══════════════════════════════════════════════════════════════════════════
# VERSION DETECTION
# ═══════════════════════════════════════════════════════════════════════════

function Get-LatestNodeVersion {
    Write-Info "Checking latest Node.js LTS v24.x..."
    try {
        $resp = Invoke-WebRequestSafe "https://nodejs.org/dist/index.json"
        if (-not $resp) { return $null }
        $releases = $resp.Content | ConvertFrom-Json
        foreach ($r in $releases) {
            if ($r.version -match '^v24\.' -and $r.lts) {
                Write-Info "Found: $($r.version)"
                return $r.version
            }
        }
        # If no LTS v24, return latest v24
        foreach ($r in $releases) {
            if ($r.version -match '^v24\.') {
                Write-Info "Found (non-LTS): $($r.version)"
                return $r.version
            }
        }
    } catch {
        Write-Info "Node.js version detection failed: $_"
    }
    return $null
}

function Get-LatestPythonVersion {
    Write-Info "Checking latest Python 3.x..."
    try {
        $resp = Invoke-WebRequestSafe "https://endoflife.date/api/python.json"
        if (-not $resp) { return $null }
        $releases = $resp.Content | ConvertFrom-Json
        foreach ($r in $releases) {
            if ($r.cycle -match '^3\.' -and $r.latest) {
                Write-Info "Found: $($r.latest)"
                return $r.latest
            }
        }
    } catch {
        Write-Info "Python version detection failed: $_"
    }
    return $null
}

function Get-LatestGitHubRelease {
    param([string]$Repo, [string]$Label)
    Write-Info "Checking latest $Label..."
    try {
        $resp = Invoke-WebRequestSafe "https://api.github.com/repos/$Repo/releases/latest"
        if (-not $resp) { return $null }
        $release = $resp.Content | ConvertFrom-Json
        $tag = $release.tag_name
        # Strip leading 'v' or other prefixes
        $ver = $tag -replace '^[vV]', '' -replace '^azure-cli-', ''
        Write-Info "Found: $ver"
        return @{ Version = $ver; Assets = $release.assets; Body = $release.body }
    } catch {
        Write-Info "$Label version detection failed: $_"
        return $null
    }
}

function Get-LatestNpmVersion {
    param([string]$Package)
    Write-Info "Checking npm: $Package..."
    if (-not (Test-CommandExists "npm")) {
        Write-Info "npm not available"
        return $null
    }
    try {
        $ver = npm view $Package version 2>&1
        if ($LASTEXITCODE -eq 0 -and $ver -match '^\d+') {
            Write-Info "Found: $ver"
            return $ver.Trim()
        }
    } catch { }
    return $null
}

# ═══════════════════════════════════════════════════════════════════════════
# SHA256 DETECTION
# ═══════════════════════════════════════════════════════════════════════════

function Get-NodeSha256 {
    param([string]$Version)
    Write-Info "Fetching Node.js SHA256..."
    try {
        $resp = Invoke-WebRequestSafe "https://nodejs.org/dist/$Version/SHASUMS256.txt"
        if (-not $resp) { return "" }
        $lines = $resp.Content -split "`n"
        $target = "node-$Version-x64.msi"
        foreach ($line in $lines) {
            if ($line -match "^([a-f0-9]{64})\s+$([regex]::Escape($target))") {
                Write-Info "Found SHA256 for $target"
                return $Matches[1]
            }
        }
    } catch { }
    return ""
}

function Get-PythonSha256 {
    param([string]$Version)
    Write-Info "Fetching Python SHA256..."
    # Try the .sha256 sidecar file
    $url = "https://www.python.org/ftp/python/$Version/python-$Version-amd64.exe.sha256"
    try {
        $resp = Invoke-WebRequestSafe $url
        if ($resp -and $resp.Content -match '([a-f0-9]{64})') {
            Write-Info "Found Python SHA256"
            return $Matches[1]
        }
    } catch { }
    return ""
}

function Get-GitHubReleaseSha256 {
    param($ReleaseInfo, [string]$InstallerPattern, [string]$Label)
    if (-not $ReleaseInfo) { return "" }
    Write-Info "Checking $Label release for SHA256..."

    # Check for a checksums asset
    foreach ($asset in $ReleaseInfo.Assets) {
        $name = $asset.name
        if ($name -match '(sha256|checksum|SHASUMS)' -and $name -match '\.(txt|sha256)$') {
            try {
                $resp = Invoke-WebRequestSafe $asset.browser_download_url
                if ($resp -and $resp.Content -match "([a-f0-9]{64})\s+.*$([regex]::Escape($InstallerPattern))") {
                    Write-Info "Found SHA256 from checksums file"
                    return $Matches[1]
                }
                # Also try pattern: hash on its own line followed by filename
                $cLines = $resp.Content -split "`n"
                foreach ($cl in $cLines) {
                    if ($cl -match $InstallerPattern -and $cl -match '([a-f0-9]{64})') {
                        Write-Info "Found SHA256 from checksums file"
                        return $Matches[1]
                    }
                }
            } catch { }
        }
    }

    # Check release body for hashes
    if ($ReleaseInfo.Body -match "([a-f0-9]{64})\s+.*$([regex]::Escape($InstallerPattern))") {
        Write-Info "Found SHA256 in release notes"
        return $Matches[1]
    }

    return ""
}

# ═══════════════════════════════════════════════════════════════════════════
# SOURCE IMAGE DETECTION
# ═══════════════════════════════════════════════════════════════════════════

function Get-LatestSourceImageVersion {
    param([string]$Location, [string]$Sku)
    Write-Info "Querying Azure for latest source image version..."
    if (-not (Test-CommandExists "az")) { return $null }
    try {
        $json = az vm image list --location $Location --publisher MicrosoftWindowsDesktop --offer windows-11 --sku $Sku --all --output json 2>&1
        if ($LASTEXITCODE -ne 0) { return $null }
        $images = $json | ConvertFrom-Json
        if ($images.Count -eq 0) { return $null }
        $sorted = $images | Sort-Object { $_.version } -Descending
        $latest = $sorted[0].version
        Write-Info "Found: $latest"
        return $latest
    } catch {
        Write-Info "Source image detection failed: $_"
        return $null
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════

try {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  W365Claw — Terraform Variables Initializer" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    # Resolve paths
    if (Test-Path $TerraformDir) {
        $TerraformDir = (Resolve-Path $TerraformDir).Path
    }
    $tfvarsPath = Join-Path $TerraformDir "terraform.tfvars"

    # ── Parse existing tfvars ──
    Write-Step "Parsing existing terraform.tfvars"
    $existing = Read-TfVars $tfvarsPath
    if ($existing.Count -gt 0) {
        Write-Success "Loaded $($existing.Count) values from existing file"
    } else {
        Write-Info "No existing terraform.tfvars found — using defaults"
    }

    # ── Azure CLI Check ──
    Write-Step "Azure CLI Check"
    $subscriptionId = if ($existing["subscription_id"]) { $existing["subscription_id"] } else { "00000000-0000-0000-0000-000000000000" }

    if (Test-CommandExists "az") {
        try {
            $acctJson = az account show 2>&1
            if ($LASTEXITCODE -eq 0) {
                $acct = $acctJson | ConvertFrom-Json
                $subscriptionId = $acct.id
                Write-Success "Logged in: $($acct.name) ($subscriptionId)"
            } else {
                Write-Warn "Not logged in to Azure CLI"
                if (-not $Force) {
                    $doLogin = Read-Host "  Run 'az login'? [Y/n]"
                    if ($doLogin -eq "" -or $doLogin -eq "Y" -or $doLogin -eq "y") {
                        az login 2>&1 | Out-Null
                        $acctJson = az account show 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            $acct = $acctJson | ConvertFrom-Json
                            $subscriptionId = $acct.id
                            Write-Success "Logged in: $($acct.name) ($subscriptionId)"
                        }
                    }
                }
            }
        } catch {
            Write-Warn "Azure CLI check failed: $_"
        }
    } else {
        Write-Warn "Azure CLI not installed — subscription_id will need manual entry"
    }

    # ── Auto-detect versions ──
    Write-Step "Auto-detecting latest software versions"

    $detectedNode = Get-LatestNodeVersion
    $detectedPython = Get-LatestPythonVersion
    $gitRelease = Get-LatestGitHubRelease "git-for-windows/git" "Git for Windows"
    $pwshRelease = Get-LatestGitHubRelease "PowerShell/PowerShell" "PowerShell"
    $azCliRelease = Get-LatestGitHubRelease "Azure/azure-cli" "Azure CLI"
    $detectedOpenspec = Get-LatestNpmVersion "@fission-ai/openspec"

    # Helper: pick detected or existing or hardcoded default
    function Pick-Default {
        param([string]$Detected, [string]$ExistingKey, [string]$Fallback)
        if ($Detected) { return $Detected }
        if ($existing[$ExistingKey]) { return $existing[$ExistingKey] }
        return $Fallback
    }

    $defaults = @{}
    $defaults["subscription_id"]       = $subscriptionId
    $defaults["location"]              = if ($existing["location"]) { $existing["location"] } else { "eastus2" }
    $defaults["resource_group_name"]   = if ($existing["resource_group_name"]) { $existing["resource_group_name"] } else { "rg-w365-images" }
    $defaults["gallery_name"]          = if ($existing["gallery_name"]) { $existing["gallery_name"] } else { "acgW365Dev" }
    $defaults["image_definition_name"] = if ($existing["image_definition_name"]) { $existing["image_definition_name"] } else { "W365-W11-25H2-ENU" }
    $defaults["image_publisher"]       = if ($existing["image_publisher"]) { $existing["image_publisher"] } else { "BigHatGroupInc" }
    $defaults["image_offer"]           = if ($existing["image_offer"]) { $existing["image_offer"] } else { "W365-W11-25H2-ENU" }
    $defaults["image_sku"]             = if ($existing["image_sku"]) { $existing["image_sku"] } else { "W11-25H2-ENT-Dev" }
    $defaults["image_version"]         = if ($existing["image_version"]) { $existing["image_version"] } else { "1.0.0" }
    $defaults["exclude_from_latest"]   = if ($existing["exclude_from_latest"]) { $existing["exclude_from_latest"] } else { "true" }
    $defaults["replica_count"]         = if ($existing["replica_count"]) { $existing["replica_count"] } else { "1" }
    $defaults["build_vm_size"]         = if ($existing["build_vm_size"]) { $existing["build_vm_size"] } else { "Standard_D4s_v5" }
    $defaults["build_timeout_minutes"] = if ($existing["build_timeout_minutes"]) { $existing["build_timeout_minutes"] } else { "120" }
    $defaults["os_disk_size_gb"]       = if ($existing["os_disk_size_gb"]) { $existing["os_disk_size_gb"] } else { "128" }
    $defaults["source_image_publisher"]= if ($existing["source_image_publisher"]) { $existing["source_image_publisher"] } else { "MicrosoftWindowsDesktop" }
    $defaults["source_image_offer"]    = if ($existing["source_image_offer"]) { $existing["source_image_offer"] } else { "windows-11" }
    $defaults["source_image_sku"]      = if ($existing["source_image_sku"]) { $existing["source_image_sku"] } else { "win11-25h2-ent" }

    $defaults["node_version"]          = Pick-Default $detectedNode "node_version" "v24.13.1"
    $defaults["python_version"]        = Pick-Default $detectedPython "python_version" "3.14.3"
    $defaults["git_version"]           = Pick-Default $(if ($gitRelease) { $gitRelease.Version } else { $null }) "git_version" "2.53.0"
    $defaults["pwsh_version"]          = Pick-Default $(if ($pwshRelease) { $pwshRelease.Version } else { $null }) "pwsh_version" "7.4.13"
    $defaults["azure_cli_version"]     = Pick-Default $(if ($azCliRelease) { $azCliRelease.Version } else { $null }) "azure_cli_version" "2.83.0"
    $defaults["openspec_version"]      = Pick-Default $detectedOpenspec "openspec_version" "0.9.1"

    $defaults["openclaw_default_model"]= if ($existing["openclaw_default_model"]) { $existing["openclaw_default_model"] } else { "anthropic/claude-opus-4-6" }
    $defaults["openclaw_gateway_port"] = if ($existing["openclaw_gateway_port"]) { $existing["openclaw_gateway_port"] } else { "18789" }

    $defaults["skills_repo_url"]       = if ($existing["skills_repo_url"]) { $existing["skills_repo_url"] } else { "" }

    # ── Auto-detect source image version ──
    Write-Step "Auto-detecting source image version"
    $detectedSourceImage = Get-LatestSourceImageVersion $defaults["location"] $defaults["source_image_sku"]
    $defaults["source_image_version"] = Pick-Default $detectedSourceImage "source_image_version" "26200.7840.260206"

    # ── Auto-detect SHA256 checksums ──
    Write-Step "Auto-detecting SHA256 checksums"

    $defaults["node_sha256"]      = if ($existing["node_sha256"]) { $existing["node_sha256"] } else { "" }
    $defaults["python_sha256"]    = if ($existing["python_sha256"]) { $existing["python_sha256"] } else { "" }
    $defaults["pwsh_sha256"]      = if ($existing["pwsh_sha256"]) { $existing["pwsh_sha256"] } else { "" }
    $defaults["git_sha256"]       = if ($existing["git_sha256"]) { $existing["git_sha256"] } else { "" }
    $defaults["azure_cli_sha256"] = if ($existing["azure_cli_sha256"]) { $existing["azure_cli_sha256"] } else { "" }

    # Only fetch checksums if version changed or empty
    $nodeSha = Get-NodeSha256 $defaults["node_version"]
    if ($nodeSha) { $defaults["node_sha256"] = $nodeSha }

    $pythonSha = Get-PythonSha256 $defaults["python_version"]
    if ($pythonSha) { $defaults["python_sha256"] = $pythonSha }

    $pwshSha = Get-GitHubReleaseSha256 $pwshRelease "PowerShell-$($defaults['pwsh_version'])-win-x64.msi" "PowerShell"
    if ($pwshSha) { $defaults["pwsh_sha256"] = $pwshSha }

    $gitSha = Get-GitHubReleaseSha256 $gitRelease "Git-$($defaults['git_version'])-64-bit.exe" "Git"
    if ($gitSha) { $defaults["git_sha256"] = $gitSha }

    $azCliSha = Get-GitHubReleaseSha256 $azCliRelease "azure-cli-$($defaults['azure_cli_version'])-x64.msi" "Azure CLI"
    if ($azCliSha) { $defaults["azure_cli_sha256"] = $azCliSha }

    # ── Tags ──
    $defaultTags = @{}
    if ($existing["tags"] -is [hashtable]) {
        foreach ($k in $existing["tags"].Keys) {
            $defaultTags[$k] = $existing["tags"][$k]
        }
    }
    if ($defaultTags.Count -eq 0) {
        $defaultTags = @{
            workload    = "Windows365"
            purpose     = "DeveloperImages"
            managed_by  = "PlatformEngineering"
            iac         = "Terraform"
            cost_center = "Engineering"
        }
    }

    # ═══════════════════════════════════════════════════════════════════════
    # PROMPT FOR ALL VALUES
    # ═══════════════════════════════════════════════════════════════════════

    Write-Step "Environment & Subscription"
    $vals = @{}
    $vals["subscription_id"]       = Read-ValueWithDefault "Subscription ID" $defaults["subscription_id"]
    $vals["location"]              = Read-ValueWithDefault "Location" $defaults["location"]
    $vals["resource_group_name"]   = Read-ValueWithDefault "Resource Group" $defaults["resource_group_name"]

    Write-Step "Gallery"
    $vals["gallery_name"]          = Read-ValueWithDefault "Gallery Name" $defaults["gallery_name"] '^[a-zA-Z0-9]+$' "Gallery name must be alphanumeric only"
    $vals["image_definition_name"] = Read-ValueWithDefault "Image Definition Name" $defaults["image_definition_name"]
    $vals["image_publisher"]       = Read-ValueWithDefault "Image Publisher" $defaults["image_publisher"]
    $vals["image_offer"]           = Read-ValueWithDefault "Image Offer" $defaults["image_offer"]
    $vals["image_sku"]             = Read-ValueWithDefault "Image SKU" $defaults["image_sku"]

    Write-Step "Image Version"
    $vals["image_version"]         = Read-ValueWithDefault "Image Version" $defaults["image_version"] '^\d+\.\d+\.\d+$' "Must be Major.Minor.Patch format"
    $vals["exclude_from_latest"]   = Read-BoolWithDefault "Exclude from Latest" $defaults["exclude_from_latest"]
    $vals["replica_count"]         = Read-IntWithDefault "Replica Count" $defaults["replica_count"]

    Write-Step "Build VM"
    $vals["build_vm_size"]         = Read-ValueWithDefault "Build VM Size" $defaults["build_vm_size"]
    $vals["build_timeout_minutes"] = Read-IntWithDefault "Build Timeout (minutes)" $defaults["build_timeout_minutes"]
    $vals["os_disk_size_gb"]       = Read-IntWithDefault "OS Disk Size (GB)" $defaults["os_disk_size_gb"]

    Write-Step "Source Image"
    $vals["source_image_publisher"]= Read-ValueWithDefault "Source Image Publisher" $defaults["source_image_publisher"]
    $vals["source_image_offer"]    = Read-ValueWithDefault "Source Image Offer" $defaults["source_image_offer"]
    $vals["source_image_sku"]      = Read-ValueWithDefault "Source Image SKU" $defaults["source_image_sku"]
    $vals["source_image_version"]  = Read-ValueWithDefault "Source Image Version" $defaults["source_image_version"]

    Write-Step "Software Versions"
    $vals["node_version"]          = Read-ValueWithDefault "Node.js Version" $defaults["node_version"]
    $vals["python_version"]        = Read-ValueWithDefault "Python Version" $defaults["python_version"]
    $vals["git_version"]           = Read-ValueWithDefault "Git Version" $defaults["git_version"]
    $vals["pwsh_version"]          = Read-ValueWithDefault "PowerShell Version" $defaults["pwsh_version"]
    $vals["azure_cli_version"]     = Read-ValueWithDefault "Azure CLI Version" $defaults["azure_cli_version"]
    $vals["openspec_version"]      = Read-ValueWithDefault "OpenSpec Version" $defaults["openspec_version"]

    Write-Step "SHA256 Checksums (leave empty to skip verification)"
    $vals["node_sha256"]           = Read-ValueWithDefault "Node SHA256" $defaults["node_sha256"]
    $vals["python_sha256"]         = Read-ValueWithDefault "Python SHA256" $defaults["python_sha256"]
    $vals["pwsh_sha256"]           = Read-ValueWithDefault "PowerShell SHA256" $defaults["pwsh_sha256"]
    $vals["git_sha256"]            = Read-ValueWithDefault "Git SHA256" $defaults["git_sha256"]
    $vals["azure_cli_sha256"]      = Read-ValueWithDefault "Azure CLI SHA256" $defaults["azure_cli_sha256"]

    Write-Step "OpenClaw Configuration"
    $vals["openclaw_default_model"]= Read-ValueWithDefault "OpenClaw Default Model" $defaults["openclaw_default_model"]
    $vals["openclaw_gateway_port"] = Read-IntWithDefault "OpenClaw Gateway Port" $defaults["openclaw_gateway_port"]

    Write-Step "Agent Skills & MCP Servers"
    $vals["skills_repo_url"]       = Read-ValueWithDefault "Skills Repository URL (empty to skip)" $defaults["skills_repo_url"]

    Write-Step "Tags"
    $finalTags = [ordered]@{}
    foreach ($tagKey in ($defaultTags.Keys | Sort-Object)) {
        $tagVal = Read-ValueWithDefault "Tag '$tagKey'" $defaultTags[$tagKey]
        if ($tagVal) { $finalTags[$tagKey] = $tagVal }
    }

    if (-not $Force) {
        $addMore = Read-Host "  Add more tags? [y/N]"
        while ($addMore -eq "y" -or $addMore -eq "Y") {
            $newKey = Read-Host "  Tag key"
            if (-not $newKey) { break }
            $newVal = Read-Host "  Tag value"
            $finalTags[$newKey] = $newVal
            $addMore = Read-Host "  Add another? [y/N]"
        }
    }

    # ═══════════════════════════════════════════════════════════════════════
    # SUMMARY
    # ═══════════════════════════════════════════════════════════════════════

    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  Summary — terraform.tfvars" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""

    # Ordered list of keys for display
    $displayOrder = @(
        "subscription_id", "location", "resource_group_name",
        "gallery_name", "image_definition_name", "image_publisher", "image_offer", "image_sku",
        "image_version", "exclude_from_latest", "replica_count",
        "build_vm_size", "build_timeout_minutes", "os_disk_size_gb",
        "source_image_publisher", "source_image_offer", "source_image_sku", "source_image_version",
        "node_version", "python_version", "git_version", "pwsh_version", "azure_cli_version",
        "openspec_version",
        "node_sha256", "python_sha256", "pwsh_sha256", "git_sha256", "azure_cli_sha256",
        "openclaw_default_model", "openclaw_gateway_port",
        "skills_repo_url"
    )

    $maxKeyLen = ($displayOrder | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum + 2
    foreach ($key in $displayOrder) {
        $display = if ($vals[$key]) { $vals[$key] } else { "(empty)" }
        $paddedKey = $key.PadRight($maxKeyLen)
        Write-Host "  $paddedKey = $display"
    }

    Write-Host ""
    Write-Host "  Tags:" -ForegroundColor Cyan
    foreach ($k in $finalTags.Keys) {
        Write-Host "    $k = $($finalTags[$k])"
    }
    Write-Host ""

    # ── Confirmation ──
    if (-not $Force) {
        $confirm = Read-Host "Write terraform.tfvars? [Y/n]"
        if ($confirm -ne "" -and $confirm -ne "Y" -and $confirm -ne "y") {
            Write-Warn "Aborted. No changes made."
            exit 0
        }
    }

    # ═══════════════════════════════════════════════════════════════════════
    # WRITE TERRAFORM.TFVARS
    # ═══════════════════════════════════════════════════════════════════════

    # Determine which keys are bools and ints (unquoted)
    $boolKeys = @("exclude_from_latest")
    $intKeys = @("replica_count", "build_timeout_minutes", "os_disk_size_gb", "openclaw_gateway_port")

    function Format-TfValue {
        param([string]$Key, [string]$Value)
        if ($boolKeys -contains $Key) { return $Value }
        if ($intKeys -contains $Key) { return $Value }
        return "`"$Value`""
    }

    # Build aligned output
    $tagBlock = @()
    foreach ($k in $finalTags.Keys) {
        $tagBlock += "  $($k.PadRight(12))= `"$($finalTags[$k])`""
    }

    $output = @"
# ── Environment-Specific Values ──
# Copy this file and adjust for your environment.
# Do NOT commit secrets to source control.

subscription_id       = $(Format-TfValue "subscription_id" $vals["subscription_id"])
location              = $(Format-TfValue "location" $vals["location"])
resource_group_name   = $(Format-TfValue "resource_group_name" $vals["resource_group_name"])

# Gallery
gallery_name          = $(Format-TfValue "gallery_name" $vals["gallery_name"])
image_definition_name = $(Format-TfValue "image_definition_name" $vals["image_definition_name"])
image_publisher       = $(Format-TfValue "image_publisher" $vals["image_publisher"])
image_offer           = $(Format-TfValue "image_offer" $vals["image_offer"])
image_sku             = $(Format-TfValue "image_sku" $vals["image_sku"])

# Image Version
image_version         = $(Format-TfValue "image_version" $vals["image_version"])
exclude_from_latest   = $(Format-TfValue "exclude_from_latest" $vals["exclude_from_latest"])     # Set to false after pilot validation
replica_count         = $(Format-TfValue "replica_count" $vals["replica_count"])

# Build VM
build_vm_size         = $(Format-TfValue "build_vm_size" $vals["build_vm_size"])
build_timeout_minutes = $(Format-TfValue "build_timeout_minutes" $vals["build_timeout_minutes"])
os_disk_size_gb       = $(Format-TfValue "os_disk_size_gb" $vals["os_disk_size_gb"])

# Source Image (pinned for reproducibility)
source_image_publisher = $(Format-TfValue "source_image_publisher" $vals["source_image_publisher"])
source_image_offer     = $(Format-TfValue "source_image_offer" $vals["source_image_offer"])
source_image_sku       = $(Format-TfValue "source_image_sku" $vals["source_image_sku"])
source_image_version   = $(Format-TfValue "source_image_version" $vals["source_image_version"])

# Software Versions (pinned)
node_version          = $(Format-TfValue "node_version" $vals["node_version"])
python_version        = $(Format-TfValue "python_version" $vals["python_version"])
git_version           = $(Format-TfValue "git_version" $vals["git_version"])
pwsh_version          = $(Format-TfValue "pwsh_version" $vals["pwsh_version"])
azure_cli_version     = $(Format-TfValue "azure_cli_version" $vals["azure_cli_version"])
openspec_version      = $(Format-TfValue "openspec_version" $vals["openspec_version"])

# Installer SHA256 Checksums (update when bumping versions)
# Obtain from official release pages. Leave empty to skip verification.
node_sha256           = $(Format-TfValue "node_sha256" $vals["node_sha256"])
python_sha256         = $(Format-TfValue "python_sha256" $vals["python_sha256"])
pwsh_sha256           = $(Format-TfValue "pwsh_sha256" $vals["pwsh_sha256"])
git_sha256            = $(Format-TfValue "git_sha256" $vals["git_sha256"])
azure_cli_sha256      = $(Format-TfValue "azure_cli_sha256" $vals["azure_cli_sha256"])

# OpenClaw
openclaw_default_model = $(Format-TfValue "openclaw_default_model" $vals["openclaw_default_model"])
openclaw_gateway_port  = $(Format-TfValue "openclaw_gateway_port" $vals["openclaw_gateway_port"])

# Agent Skills & MCP Servers
skills_repo_url        = $(Format-TfValue "skills_repo_url" $vals["skills_repo_url"])
mcp_packages           = ["@perplexity-ai/mcp-server"]

# Tags
tags = {
$($tagBlock -join "`n")
}
"@

    # Ensure terraform directory exists
    if (-not (Test-Path $TerraformDir)) {
        New-Item -ItemType Directory -Path $TerraformDir -Force | Out-Null
    }

    $output | Set-Content -Path $tfvarsPath -Encoding UTF8 -Force
    Write-Host ""
    Write-Success "Written to $tfvarsPath"
    Write-Host ""

    exit 0

} catch {
    Write-Host ""
    Write-Err "Fatal error: $($_.Exception.Message)"
    Write-Err "At: $($_.ScriptStackTrace)"
    exit 1
}
"@
