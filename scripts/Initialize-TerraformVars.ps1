#requires -Version 5.1
<#
.SYNOPSIS
    Detects current software/image versions and writes terraform/terraform.tfvars.

.DESCRIPTION
    This script auto-detects the latest supported versions and installer checksums
    required by W365Claw, then writes terraform.tfvars after operator confirmation.

    Detected values:
      - Azure subscription ID (az account show)
      - Node.js latest LTS version + MSI SHA256
      - Python latest stable version + Windows installer SHA256
      - PowerShell 7 LTS latest (7.4.x) + MSI SHA256
      - Git for Windows latest version + installer SHA256
      - Azure CLI latest version + MSI SHA256
      - Latest npm package versions:
          openclaw
          @anthropic-ai/claude-code
          @fission-ai/openspec
          @openai/codex
      - Latest Windows 11 24H2 Enterprise marketplace image version

.PARAMETER TerraformDir
    Path to the terraform/ directory. Defaults to ..\terraform relative to this script.

.PARAMETER TfvarsPath
    Optional explicit path for terraform.tfvars. Defaults to <TerraformDir>/terraform.tfvars.

.PARAMETER Force
    Skip confirmation prompt before writing terraform.tfvars.

.EXAMPLE
    .\Initialize-TerraformVars.ps1

.EXAMPLE
    .\Initialize-TerraformVars.ps1 -WhatIf

.EXAMPLE
    .\Initialize-TerraformVars.ps1 -Force
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
param(
    [string]$TerraformDir = (Join-Path $PSScriptRoot "..\terraform"),
    [string]$TfvarsPath,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ═══════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

function Test-CommandExists {
    param([Parameter(Mandatory = $true)][string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Confirm-Action {
    param([Parameter(Mandatory = $true)][string]$Message)

    if ($Force -or $WhatIfPreference) { return $true }

    $response = Read-Host "$Message [Y/n]"
    return ($response -eq "" -or $response -eq "Y" -or $response -eq "y")
}

function Invoke-ApiGet {
    param([Parameter(Mandatory = $true)][string]$Uri)

    $headers = @{
        "User-Agent" = "W365Claw-Initialize-TerraformVars"
    }

    if ($Uri -like "https://api.github.com/*") {
        $headers["Accept"] = "application/vnd.github+json"
        $headers["X-GitHub-Api-Version"] = "2022-11-28"
    }

    return Invoke-RestMethod -Uri $Uri -Method Get -Headers $headers
}

function ConvertTo-Version {
    param([Parameter(Mandatory = $true)][string]$Value)
    return [version]($Value -replace '[^0-9\.].*$', '')
}

function Get-VersionSortKey {
    param([Parameter(Mandatory = $true)][string]$Value)

    $parts = $Value -split '\.'
    $normalized = foreach ($part in $parts) {
        $num = 0
        [void][int]::TryParse($part, [ref]$num)
        $num.ToString("D10")
    }
    return ($normalized -join ".")
}

function Get-GitHubReleases {
    param([Parameter(Mandatory = $true)][string]$Repo)
    return Invoke-ApiGet "https://api.github.com/repos/$Repo/releases?per_page=100"
}

function Get-ShaFromDigest {
    param([AllowNull()][string]$Digest)
    if ($null -eq $Digest) { return $null }
    if ($Digest -match '^sha256:([a-fA-F0-9]{64})$') {
        return $Matches[1].ToLowerInvariant()
    }
    return $null
}

function Get-ShaFromText {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$AssetName
    )

    if ($Text -match '(?im)^\s*([a-fA-F0-9]{64})\s*$') {
        return $Matches[1].ToLowerInvariant()
    }

    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\s*([a-fA-F0-9]{64})\s+[\*\s]?(.+?)\s*$') {
            if ($Matches[2].Trim() -eq $AssetName) {
                return $Matches[1].ToLowerInvariant()
            }
        }
        if ($line -match '^\s*SHA256\s*\((.+?)\)\s*=\s*([a-fA-F0-9]{64})\s*$') {
            if ($Matches[1].Trim() -eq $AssetName) {
                return $Matches[2].ToLowerInvariant()
            }
        }
    }

    return $null
}

function Get-GitHubAssetSha256 {
    param(
        [Parameter(Mandatory = $true)]$Release,
        [Parameter(Mandatory = $true)]$Asset
    )

    $digestSha = Get-ShaFromDigest -Digest $Asset.digest
    if ($digestSha) { return $digestSha }

    $exactChecksumAssets = @(
        "$($Asset.name).sha256",
        "$($Asset.name).sha256sum",
        "$($Asset.name).sha256.txt"
    )

    $candidateAssets = @()
    $candidateAssets += $Release.assets | Where-Object { $exactChecksumAssets -contains $_.name }
    $candidateAssets += $Release.assets | Where-Object { $_.name -match 'sha256|checksums?|hashes?' }

    foreach ($checksumAsset in ($candidateAssets | Sort-Object name -Unique)) {
        try {
            $text = [string](Invoke-ApiGet -Uri $checksumAsset.browser_download_url)
            $sha = Get-ShaFromText -Text $text -AssetName $Asset.name
            if ($sha) { return $sha }

            if ($text -match '(?im)\b([a-fA-F0-9]{64})\b') {
                return $Matches[1].ToLowerInvariant()
            }
        } catch {
            continue
        }
    }

    throw "Unable to resolve SHA256 for asset '$($Asset.name)' from release '$($Release.tag_name)'."
}

function Get-NodeReleaseInfo {
    $index = Invoke-ApiGet "https://nodejs.org/dist/index.json"
    $ltsRelease = $index |
        Where-Object { $_.lts -and $_.version -match '^v\d+\.\d+\.\d+$' } |
        Sort-Object { ConvertTo-Version $_.version.TrimStart("v") } -Descending |
        Select-Object -First 1

    if (-not $ltsRelease) {
        throw "Unable to find latest Node.js LTS release from Node.js index API."
    }

    $version = $ltsRelease.version
    $assetName = "node-$version-x64.msi"
    $shasums = [string](Invoke-ApiGet "https://nodejs.org/dist/$version/SHASUMS256.txt")
    $sha = Get-ShaFromText -Text $shasums -AssetName $assetName

    if (-not $sha) {
        throw "Unable to parse Node.js SHA256 for $assetName from SHASUMS256.txt."
    }

    return [ordered]@{
        version = $version
        sha256  = $sha
        asset   = $assetName
    }
}

function Get-PythonReleaseInfo {
    $release = Get-GitHubReleases "python/cpython" |
        Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -match '^v\d+\.\d+\.\d+$' } |
        Sort-Object { ConvertTo-Version $_.tag_name.TrimStart("v") } -Descending |
        Select-Object -First 1

    if (-not $release) {
        throw "Unable to find latest Python stable release."
    }

    $asset = $release.assets |
        Where-Object { $_.name -match '^python-\d+\.\d+\.\d+-amd64\.exe$' } |
        Select-Object -First 1

    if (-not $asset) {
        throw "Unable to find Python amd64 Windows installer in release '$($release.tag_name)'."
    }

    $sha = Get-GitHubAssetSha256 -Release $release -Asset $asset

    return [ordered]@{
        version = ($release.tag_name.TrimStart("v"))
        sha256  = $sha
        asset   = $asset.name
    }
}

function Get-PowerShellReleaseInfo {
    $release = Get-GitHubReleases "PowerShell/PowerShell" |
        Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -match '^v7\.4\.\d+$' } |
        Sort-Object { ConvertTo-Version $_.tag_name.TrimStart("v") } -Descending |
        Select-Object -First 1

    if (-not $release) {
        throw "Unable to find latest PowerShell 7.4 LTS release."
    }

    $asset = $release.assets |
        Where-Object { $_.name -match '^PowerShell-\d+\.\d+\.\d+-win-x64\.msi$' } |
        Select-Object -First 1

    if (-not $asset) {
        throw "Unable to find PowerShell x64 MSI in release '$($release.tag_name)'."
    }

    $sha = Get-GitHubAssetSha256 -Release $release -Asset $asset

    return [ordered]@{
        version = ($release.tag_name.TrimStart("v"))
        sha256  = $sha
        asset   = $asset.name
    }
}

function Get-GitWindowsReleaseInfo {
    $release = Get-GitHubReleases "git-for-windows/git" |
        Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -match '^v\d+\.\d+\.\d+(\.windows\.\d+)?$' } |
        Sort-Object { ConvertTo-Version (($_.tag_name.TrimStart("v")) -replace '\.windows\.\d+$', '') } -Descending |
        Select-Object -First 1

    if (-not $release) {
        throw "Unable to find latest Git for Windows release."
    }

    $asset = $release.assets |
        Where-Object { $_.name -match '^Git-\d+\.\d+\.\d+(\.\d+)?-64-bit\.exe$' } |
        Sort-Object name |
        Select-Object -Last 1

    if (-not $asset) {
        throw "Unable to find Git for Windows 64-bit installer in release '$($release.tag_name)'."
    }

    $version = $release.tag_name.TrimStart("v") -replace '\.windows\.\d+$', ''
    $sha = Get-GitHubAssetSha256 -Release $release -Asset $asset

    return [ordered]@{
        version = $version
        sha256  = $sha
        asset   = $asset.name
    }
}

function Get-AzureCliReleaseInfo {
    $release = Get-GitHubReleases "Azure/azure-cli" |
        Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -match '^azure-cli-\d+\.\d+\.\d+$' } |
        Sort-Object { ConvertTo-Version (($_.tag_name) -replace '^azure-cli-', '') } -Descending |
        Select-Object -First 1

    if (-not $release) {
        throw "Unable to find latest Azure CLI stable release."
    }

    $asset = $release.assets |
        Where-Object { $_.name -match '^azure-cli-\d+\.\d+\.\d+-x64\.msi$' } |
        Select-Object -First 1

    if (-not $asset) {
        throw "Unable to find Azure CLI x64 MSI installer in release '$($release.tag_name)'."
    }

    $version = ($release.tag_name -replace '^azure-cli-', '')
    $sha = Get-GitHubAssetSha256 -Release $release -Asset $asset

    return [ordered]@{
        version = $version
        sha256  = $sha
        asset   = $asset.name
    }
}

function Get-NpmLatestVersion {
    param([Parameter(Mandatory = $true)][string]$PackageName)
    $encodedPackageName = [Uri]::EscapeDataString($PackageName)
    $result = Invoke-ApiGet "https://registry.npmjs.org/$encodedPackageName/latest"
    return [string]$result.version
}

function Invoke-AzJson {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    if (-not (Test-CommandExists "az")) {
        throw "Azure CLI (az) is not installed or not in PATH."
    }

    $output = & az @Arguments --output json 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Arguments -join ' ')"
    }

    if (-not $output) {
        throw "Azure CLI command returned no output: az $($Arguments -join ' ')"
    }

    return ($output | ConvertFrom-Json)
}

function Get-AzureSubscriptionId {
    $account = Invoke-AzJson -Arguments @("account", "show")
    if (-not $account.id) {
        throw "Azure CLI is authenticated but account ID was not returned."
    }
    return [string]$account.id
}

function Get-LatestWindowsImageVersion {
    $images = Invoke-AzJson -Arguments @(
        "vm", "image", "list",
        "--publisher", "MicrosoftWindowsDesktop",
        "--offer", "windows-11",
        "--sku", "win11-24h2-ent",
        "--all"
    )

    if (-not $images -or $images.Count -eq 0) {
        throw "No marketplace images found for MicrosoftWindowsDesktop/windows-11/win11-24h2-ent."
    }

    $latest = $images |
        Where-Object { $_.version -match '^\d+(\.\d+)+$' } |
        Sort-Object { Get-VersionSortKey $_.version } -Descending |
        Select-Object -First 1

    if (-not $latest) {
        throw "Unable to determine latest Windows 11 24H2 Enterprise image version."
    }

    return [string]$latest.version
}

function ConvertTo-TfvarsLine {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value
    )

    if ($Value -is [bool]) {
        return "$Name = $($Value.ToString().ToLowerInvariant())"
    }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return "$Name = $Value"
    }

    $escaped = [string]$Value -replace '\\', '\\' -replace '"', '\"'
    return "$Name = `"$escaped`""
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════

$TerraformDir = (Resolve-Path $TerraformDir -ErrorAction Stop).Path
if (-not $TfvarsPath) {
    $TfvarsPath = Join-Path $TerraformDir "terraform.tfvars"
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  W365Claw — Initialize Terraform Variables" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Detecting latest versions and checksums..." -ForegroundColor Yellow

$subscriptionId = Get-AzureSubscriptionId
$node = Get-NodeReleaseInfo
$python = Get-PythonReleaseInfo
$pwsh = Get-PowerShellReleaseInfo
$git = Get-GitWindowsReleaseInfo
$azCli = Get-AzureCliReleaseInfo
$openclawVersion = Get-NpmLatestVersion "openclaw"
$claudeCodeVersion = Get-NpmLatestVersion "@anthropic-ai/claude-code"
$openspecVersion = Get-NpmLatestVersion "@fission-ai/openspec"
$codexVersion = Get-NpmLatestVersion "@openai/codex"
$sourceImageVersion = Get-LatestWindowsImageVersion

$tfvarsValues = [ordered]@{
    subscription_id      = $subscriptionId
    source_image_version = $sourceImageVersion
    node_version         = $node.version
    node_sha256          = $node.sha256
    python_version       = $python.version
    python_sha256        = $python.sha256
    pwsh_version         = $pwsh.version
    pwsh_sha256          = $pwsh.sha256
    git_version          = $git.version
    git_sha256           = $git.sha256
    azure_cli_version    = $azCli.version
    azure_cli_sha256     = $azCli.sha256
    openclaw_version     = $openclawVersion
    claude_code_version  = $claudeCodeVersion
    openspec_version     = $openspecVersion
    codex_version        = $codexVersion
}

Write-Host ""
Write-Host "Detected values:" -ForegroundColor Cyan
$summary = @(
    [pscustomobject]@{ Name = "subscription_id"; Value = $subscriptionId }
    [pscustomobject]@{ Name = "source_image_version"; Value = $sourceImageVersion }
    [pscustomobject]@{ Name = "node_version"; Value = "$($node.version) ($($node.asset))" }
    [pscustomobject]@{ Name = "node_sha256"; Value = $node.sha256 }
    [pscustomobject]@{ Name = "python_version"; Value = "$($python.version) ($($python.asset))" }
    [pscustomobject]@{ Name = "python_sha256"; Value = $python.sha256 }
    [pscustomobject]@{ Name = "pwsh_version"; Value = "$($pwsh.version) ($($pwsh.asset))" }
    [pscustomobject]@{ Name = "pwsh_sha256"; Value = $pwsh.sha256 }
    [pscustomobject]@{ Name = "git_version"; Value = "$($git.version) ($($git.asset))" }
    [pscustomobject]@{ Name = "git_sha256"; Value = $git.sha256 }
    [pscustomobject]@{ Name = "azure_cli_version"; Value = "$($azCli.version) ($($azCli.asset))" }
    [pscustomobject]@{ Name = "azure_cli_sha256"; Value = $azCli.sha256 }
    [pscustomobject]@{ Name = "openclaw_version"; Value = $openclawVersion }
    [pscustomobject]@{ Name = "claude_code_version"; Value = $claudeCodeVersion }
    [pscustomobject]@{ Name = "openspec_version"; Value = $openspecVersion }
    [pscustomobject]@{ Name = "codex_version"; Value = $codexVersion }
)
$summary | Format-Table -AutoSize

if (-not (Confirm-Action "Write terraform.tfvars with these values?")) {
    Write-Host "Aborted." -ForegroundColor Yellow
    exit 0
}

$fileLines = @()
$fileLines += "# Generated by scripts/Initialize-TerraformVars.ps1"
$fileLines += "# Generated at $(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")"
$fileLines += ""
foreach ($key in $tfvarsValues.Keys) {
    $fileLines += ConvertTo-TfvarsLine -Name $key -Value $tfvarsValues[$key]
}
$content = ($fileLines -join [Environment]::NewLine) + [Environment]::NewLine

if ($PSCmdlet.ShouldProcess($TfvarsPath, "Write terraform.tfvars values")) {
    Set-Content -Path $TfvarsPath -Value $content -Encoding UTF8
    Write-Host ""
    Write-Host "✅ Wrote terraform variables to: $TfvarsPath" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "WhatIf: terraform.tfvars was not written." -ForegroundColor Yellow
}
