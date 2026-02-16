<#
.SYNOPSIS
    Prepares a Windows workstation to run the W365Claw Terraform image build.

.DESCRIPTION
    Checks, installs, and configures all prerequisites for building Windows 365
    developer images using the W365Claw Terraform solution:
      - Terraform CLI (>= 1.5.0)
      - Azure CLI (>= 2.60)
      - Git (>= 2.40)
      - Az PowerShell module (>= 12.0)
      - Azure authentication
      - Azure resource provider registration
      - Terraform initialization

    The script is idempotent — running it on an already-configured machine is a no-op.
    Works in both Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER Force
    Skip confirmation prompts and install all missing prerequisites automatically.

.PARAMETER TerraformDir
    Path to the terraform/ directory. Defaults to ..\terraform relative to this script.

.EXAMPLE
    .\Initialize-BuildWorkstation.ps1
    # Interactive mode — prompts before each installation

.EXAMPLE
    .\Initialize-BuildWorkstation.ps1 -Force
    # Non-interactive — installs everything without prompting
#>

[CmdletBinding()]
param(
    [switch]$Force,

    [string]$TerraformDir = (Join-Path $PSScriptRoot "..\terraform")
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ═══════════════════════════════════════════════════════════════════════════
# CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════

$MinVersions = @{
    Terraform = [version]"1.5.0"
    AzureCLI  = [version]"2.60.0"
    Git       = [version]"2.40.0"
    AzModule  = [version]"12.0.0"
}

$RequiredProviders = @(
    "Microsoft.Compute",
    "Microsoft.VirtualMachineImages",
    "Microsoft.Network",
    "Microsoft.ManagedIdentity"
)

$ProviderRegistrationTimeoutSeconds = 300
$ProviderRegistrationPollSeconds = 10

# ═══════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

function Update-SessionPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Get-ParsedVersion {
    <#
    .SYNOPSIS
        Extracts a version number from a string like "Terraform v1.9.5" or "git version 2.43.0.windows.1"
    #>
    param([string]$VersionString)

    if ($VersionString -match '(\d+\.\d+\.\d+)') {
        return [version]$Matches[1]
    }
    return $null
}

function Test-CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Test-WingetAvailable {
    Test-CommandExists "winget"
}

function Confirm-Action {
    param([string]$Message)

    if ($Force) { return $true }

    $response = Read-Host "$Message [Y/n]"
    return ($response -eq "" -or $response -eq "Y" -or $response -eq "y")
}

# ═══════════════════════════════════════════════════════════════════════════
# CHECK FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IsWindowsDesktop {
    $os = Get-CimInstance Win32_OperatingSystem
    $caption = $os.Caption
    return ($caption -match "Windows 1[01]" -or $caption -match "Windows 11")
}

function Get-TerraformVersion {
    if (-not (Test-CommandExists "terraform")) { return $null }
    $output = terraform version 2>&1 | Select-Object -First 1
    return Get-ParsedVersion $output
}

function Get-AzureCLIVersion {
    if (-not (Test-CommandExists "az")) { return $null }
    try {
        $output = az version 2>&1 | ConvertFrom-Json
        return Get-ParsedVersion $output.'azure-cli'
    } catch {
        return $null
    }
}

function Get-GitVersion {
    if (-not (Test-CommandExists "git")) { return $null }
    $output = git --version 2>&1
    return Get-ParsedVersion $output
}

function Get-AzModuleVersion {
    $mod = Get-Module -ListAvailable Az -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($mod) { return $mod.Version }
    return $null
}

function Test-AzureLogin {
    if (-not (Test-CommandExists "az")) { return @{ LoggedIn = $false; Subscription = $null } }
    try {
        $account = az account show 2>&1 | ConvertFrom-Json
        return @{ LoggedIn = $true; Subscription = $account.name }
    } catch {
        return @{ LoggedIn = $false; Subscription = $null }
    }
}

function Get-ProviderStatus {
    param([string]$ProviderNamespace)
    try {
        $result = az provider show --namespace $ProviderNamespace 2>&1 | ConvertFrom-Json
        return $result.registrationState
    } catch {
        return "Unknown"
    }
}

function Test-TerraformInitialized {
    $tfDir = Join-Path $TerraformDir ".terraform"
    return (Test-Path $tfDir -PathType Container)
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 1: PRE-FLIGHT CHECKS
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-PreFlightChecks {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  W365Claw Build Prerequisites — Pre-Flight Check" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    $results = [ordered]@{}

    # OS Check
    if (Test-IsWindowsDesktop) {
        $results["OS"] = @{ Status = $true; Detail = "Windows Desktop (x64)" }
    } else {
        $results["OS"] = @{ Status = $false; Detail = "Not Windows 10/11 Desktop" }
    }

    # Admin Check
    if (Test-IsAdmin) {
        $results["Administrator"] = @{ Status = $true; Detail = "Running elevated" }
    } else {
        $results["Administrator"] = @{ Status = $false; Detail = "NOT ELEVATED — run as Administrator" }
    }

    # Terraform
    $tfVer = Get-TerraformVersion
    if ($null -eq $tfVer) {
        $results["Terraform"] = @{ Status = $false; Detail = "MISSING"; NeedsInstall = $true }
    } elseif ($tfVer -lt $MinVersions.Terraform) {
        $results["Terraform"] = @{ Status = $false; Detail = "$tfVer (need >= $($MinVersions.Terraform))"; NeedsInstall = $true }
    } else {
        $results["Terraform"] = @{ Status = $true; Detail = "$tfVer (>= $($MinVersions.Terraform))" }
    }

    # Azure CLI
    $azVer = Get-AzureCLIVersion
    if ($null -eq $azVer) {
        $results["Azure CLI"] = @{ Status = $false; Detail = "MISSING"; NeedsInstall = $true }
    } elseif ($azVer -lt $MinVersions.AzureCLI) {
        $results["Azure CLI"] = @{ Status = $false; Detail = "$azVer (need >= $($MinVersions.AzureCLI))"; NeedsInstall = $true }
    } else {
        $results["Azure CLI"] = @{ Status = $true; Detail = "$azVer (>= $($MinVersions.AzureCLI))" }
    }

    # Git
    $gitVer = Get-GitVersion
    if ($null -eq $gitVer) {
        $results["Git"] = @{ Status = $false; Detail = "MISSING"; NeedsInstall = $true }
    } elseif ($gitVer -lt $MinVersions.Git) {
        $results["Git"] = @{ Status = $false; Detail = "$gitVer (need >= $($MinVersions.Git))"; NeedsInstall = $true }
    } else {
        $results["Git"] = @{ Status = $true; Detail = "$gitVer (>= $($MinVersions.Git))" }
    }

    # Az Module
    $azModVer = Get-AzModuleVersion
    if ($null -eq $azModVer) {
        $results["Az Module"] = @{ Status = $false; Detail = "MISSING"; NeedsInstall = $true }
    } elseif ($azModVer -lt $MinVersions.AzModule) {
        $results["Az Module"] = @{ Status = $false; Detail = "$azModVer (need >= $($MinVersions.AzModule))"; NeedsInstall = $true }
    } else {
        $results["Az Module"] = @{ Status = $true; Detail = "$azModVer (>= $($MinVersions.AzModule))" }
    }

    # Azure Login
    $loginStatus = Test-AzureLogin
    if ($loginStatus.LoggedIn) {
        $results["Azure Login"] = @{ Status = $true; Detail = "Subscription: $($loginStatus.Subscription)" }
    } else {
        $results["Azure Login"] = @{ Status = $false; Detail = "NOT LOGGED IN"; NeedsLogin = $true }
    }

    # Resource Providers (only check if logged in)
    if ($loginStatus.LoggedIn) {
        foreach ($provider in $RequiredProviders) {
            $shortName = $provider -replace "Microsoft\.", "RP: "
            $state = Get-ProviderStatus $provider
            if ($state -eq "Registered") {
                $results[$shortName] = @{ Status = $true; Detail = "Registered" }
            } else {
                $results[$shortName] = @{ Status = $false; Detail = $state; NeedsRegister = $true; Provider = $provider }
            }
        }
    } else {
        foreach ($provider in $RequiredProviders) {
            $shortName = $provider -replace "Microsoft\.", "RP: "
            $results[$shortName] = @{ Status = $false; Detail = "Skipped (not logged in)" }
        }
    }

    # Terraform Init
    if (Test-Path $TerraformDir) {
        if (Test-TerraformInitialized) {
            $results["terraform init"] = @{ Status = $true; Detail = "Initialized" }
        } else {
            $results["terraform init"] = @{ Status = $false; Detail = "Not initialized"; NeedsInit = $true }
        }
    } else {
        $results["terraform init"] = @{ Status = $false; Detail = "terraform/ directory not found at $TerraformDir" }
    }

    # Print summary table
    Write-Host ""
    $maxKeyLen = ($results.Keys | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum + 2

    foreach ($key in $results.Keys) {
        $r = $results[$key]
        $icon = if ($r.Status) { "✅" } else { "❌" }
        $paddedKey = $key.PadRight($maxKeyLen)
        if ($r.Status) {
            Write-Host "  $icon $paddedKey $($r.Detail)" -ForegroundColor Green
        } else {
            Write-Host "  $icon $paddedKey $($r.Detail)" -ForegroundColor Red
        }
    }

    Write-Host ""
    return $results
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 2: INSTALLATION
# ═══════════════════════════════════════════════════════════════════════════

function Install-MissingPrerequisites {
    param([System.Collections.Specialized.OrderedDictionary]$Results)

    $hasWinget = Test-WingetAvailable
    $installed = $false

    # ── Terraform ──
    if ($Results["Terraform"].NeedsInstall) {
        if (Confirm-Action "Install Terraform via winget?") {
            if ($hasWinget) {
                Write-Host "Installing Terraform..." -ForegroundColor Yellow
                winget install Hashicorp.Terraform --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            } else {
                Write-Host "winget not available. Downloading Terraform ZIP..." -ForegroundColor Yellow
                $tfUrl = "https://releases.hashicorp.com/terraform/1.9.5/terraform_1.9.5_windows_amd64.zip"
                $tfZip = "$env:TEMP\terraform.zip"
                $tfDest = "C:\Tools\Terraform"
                Invoke-WebRequest -Uri $tfUrl -OutFile $tfZip -UseBasicParsing
                New-Item -ItemType Directory -Path $tfDest -Force | Out-Null
                Expand-Archive -Path $tfZip -DestinationPath $tfDest -Force
                Remove-Item $tfZip -Force

                # Add to system PATH
                $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
                if ($currentPath -notlike "*$tfDest*") {
                    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$tfDest", "Machine")
                    Write-Host "Added $tfDest to system PATH" -ForegroundColor Green
                }
            }
            Update-SessionPath
            $installed = $true
        }
    }

    # ── Azure CLI ──
    if ($Results["Azure CLI"].NeedsInstall) {
        if (Confirm-Action "Install Azure CLI via winget?") {
            if ($hasWinget) {
                Write-Host "Installing Azure CLI..." -ForegroundColor Yellow
                winget install Microsoft.AzureCLI --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            } else {
                Write-Host "winget not available. Download Azure CLI from https://aka.ms/installazurecliwindowsx64" -ForegroundColor Red
            }
            Update-SessionPath
            $installed = $true
        }
    }

    # ── Git ──
    if ($Results["Git"].NeedsInstall) {
        if (Confirm-Action "Install Git via winget?") {
            if ($hasWinget) {
                Write-Host "Installing Git..." -ForegroundColor Yellow
                winget install Git.Git --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            } else {
                Write-Host "winget not available. Download Git from https://git-scm.com/download/win" -ForegroundColor Red
            }
            Update-SessionPath
            $installed = $true
        }
    }

    # ── Az PowerShell Module ──
    if ($Results["Az Module"].NeedsInstall) {
        if (Confirm-Action "Install Az PowerShell module?") {
            Write-Host "Installing Az module (this may take a few minutes)..." -ForegroundColor Yellow

            # Trust PSGallery if needed
            $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
            if ($repo -and $repo.InstallationPolicy -ne "Trusted") {
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
            }

            Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
            Write-Host "Az module installed" -ForegroundColor Green
            $installed = $true
        }
    }

    # ── Azure Login ──
    if ($Results["Azure Login"].NeedsLogin -and (Test-CommandExists "az")) {
        if (Confirm-Action "Log in to Azure?") {
            Write-Host "Launching Azure login..." -ForegroundColor Yellow
            az login 2>&1 | Out-Null

            # Check for multiple subscriptions
            $subs = az account list --query "[].{Name:name, Id:id, IsDefault:isDefault}" 2>&1 | ConvertFrom-Json
            if ($subs.Count -gt 1) {
                Write-Host ""
                Write-Host "Multiple subscriptions found:" -ForegroundColor Yellow
                for ($i = 0; $i -lt $subs.Count; $i++) {
                    $default = if ($subs[$i].IsDefault) { " (current)" } else { "" }
                    Write-Host "  [$i] $($subs[$i].Name)$default"
                }
                $selection = Read-Host "Select subscription number (or press Enter for current)"
                if ($selection -ne "") {
                    $selectedSub = $subs[[int]$selection]
                    az account set --subscription $selectedSub.Id 2>&1 | Out-Null
                    Write-Host "Set subscription: $($selectedSub.Name)" -ForegroundColor Green
                }
            }
            $installed = $true
        }
    }

    # ── Resource Providers ──
    $providersToRegister = $Results.Keys | Where-Object {
        $_ -like "RP: *" -and $Results[$_].NeedsRegister
    }

    if ($providersToRegister) {
        if (Confirm-Action "Register missing Azure resource providers?") {
            foreach ($key in $providersToRegister) {
                $provider = $Results[$key].Provider
                Write-Host "Registering $provider..." -ForegroundColor Yellow
                az provider register --namespace $provider 2>&1 | Out-Null

                # Poll until registered or timeout
                $elapsed = 0
                while ($elapsed -lt $ProviderRegistrationTimeoutSeconds) {
                    $state = Get-ProviderStatus $provider
                    if ($state -eq "Registered") {
                        Write-Host "  ✅ $provider registered" -ForegroundColor Green
                        break
                    }
                    Write-Host "  Waiting for $provider ($state)..." -ForegroundColor DarkGray
                    Start-Sleep -Seconds $ProviderRegistrationPollSeconds
                    $elapsed += $ProviderRegistrationPollSeconds
                }
                if ($elapsed -ge $ProviderRegistrationTimeoutSeconds) {
                    Write-Host "  ❌ $provider registration timed out after $ProviderRegistrationTimeoutSeconds seconds" -ForegroundColor Red
                }
            }
            $installed = $true
        }
    }

    # ── Terraform Init ──
    if ($Results["terraform init"].NeedsInit -and (Test-CommandExists "terraform")) {
        if (Confirm-Action "Run terraform init?") {
            Write-Host "Running terraform init..." -ForegroundColor Yellow
            Push-Location $TerraformDir
            try {
                terraform init 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
            } finally {
                Pop-Location
            }
            $installed = $true
        }
    }

    return $installed
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════

# Resolve TerraformDir to absolute path
$TerraformDir = (Resolve-Path $TerraformDir -ErrorAction SilentlyContinue).Path
if (-not $TerraformDir) {
    $TerraformDir = Join-Path $PSScriptRoot "..\terraform"
}

# Phase 1: Check
$results = Invoke-PreFlightChecks

# Bail if not admin
if (-not $results["Administrator"].Status) {
    Write-Host "ERROR: This script must run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell → 'Run as Administrator', then re-run this script." -ForegroundColor Red
    exit 1
}

# Check if everything passes already
$failures = $results.Keys | Where-Object { -not $results[$_].Status }
if (-not $failures) {
    Write-Host "All prerequisites met. Ready to build! 🚀" -ForegroundColor Green
    Write-Host ""
    Write-Host "  cd $TerraformDir"
    Write-Host '  terraform plan -var-file="terraform.tfvars" -out tfplan'
    Write-Host "  terraform apply tfplan"
    Write-Host ""
    exit 0
}

# Phase 2: Install
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "  Installing Missing Prerequisites" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host ""

$didInstall = Install-MissingPrerequisites $results

# Phase 3: Verify
if ($didInstall) {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Post-Installation Verification" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

    Update-SessionPath
    $finalResults = Invoke-PreFlightChecks

    $finalFailures = $finalResults.Keys | Where-Object { -not $finalResults[$_].Status }
    if (-not $finalFailures) {
        Write-Host "All prerequisites met. Ready to build! 🚀" -ForegroundColor Green
        Write-Host ""
        Write-Host "  cd $TerraformDir"
        Write-Host '  terraform plan -var-file="terraform.tfvars" -out tfplan'
        Write-Host "  terraform apply tfplan"
        Write-Host ""
        exit 0
    } else {
        Write-Host "Some prerequisites could not be resolved:" -ForegroundColor Red
        foreach ($key in $finalFailures) {
            Write-Host "  ❌ $key — $($finalResults[$key].Detail)" -ForegroundColor Red
        }
        exit 1
    }
} else {
    Write-Host ""
    Write-Host "No changes made. Re-run when ready to install missing prerequisites." -ForegroundColor Yellow
    exit 1
}
