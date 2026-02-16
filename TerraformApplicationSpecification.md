# Terraform Application Specification: OpenClaw & Claude Code Developer Image for Windows 365

*Companion to: [Building an OpenClaw and Claude Code Developer Image for Windows 365 Using Azure Compute Gallery](./BuildingOpenClawforWindows365UsingAzureComputeGallery.md)*

---

## Overview

This specification defines the complete Terraform configuration to build a Windows 365-compatible developer image containing OpenClaw, Claude Code, OpenSpec, and their full dependency chain. The infrastructure uses a single resource group and Azure VM Image Builder (AIB) to produce versioned images in an Azure Compute Gallery. The solution is manually invoked via `terraform apply` — there is no CI/CD pipeline.

### What This Deploys

1. **Azure Compute Gallery** with a Windows 365-compliant image definition
2. **User-assigned managed identity** with least-privilege RBAC for AIB
3. **Azure VM Image Builder template** with inline PowerShell customizers that install Node.js, Python, PowerShell 7, VS Code, Git, GitHub Desktop, Azure CLI, OpenClaw, Claude Code, OpenSpec, and enterprise configuration

### What Is Out of Scope

- **Intune / post-provisioning configuration** — managed separately by the administrator
- **Monitoring & operations** — not covered by this solution
- **ANTHROPIC_API_KEY management** — each user manages their own API key after login
- **CI/CD pipelines** — the solution is invoked manually

### Prerequisites

- Terraform >= 1.5
- AzureRM provider >= 4.0
- Azure subscription with sufficient permissions
- The following resource providers registered:
  - `Microsoft.Compute`
  - `Microsoft.VirtualMachineImages`
  - `Microsoft.Network`
  - `Microsoft.ManagedIdentity`

### Cost Optimization

The solution is designed to minimize cost:

- **Immediate teardown**: After the image build completes, run `terraform destroy` to remove all infrastructure resources. Only the image version in the Azure Compute Gallery persists (and is needed for Windows 365 provisioning).
- **Spot instances**: The build VM uses spot pricing where available via AIB configuration to reduce compute cost.
- **Auto-shutdown**: The build timeout is set to 120 minutes; AIB automatically deallocates the build VM when the build completes or times out.
- **Single replica**: Only one replica per region — no unnecessary replication.
- **Minimal storage**: No persistent storage account; all scripts are inline in the AIB template.

**Recommended workflow**: `terraform apply` → wait for build → verify image → `terraform destroy`.

---

## Directory Structure

```
terraform/
├── main.tf                          # Root module orchestration
├── variables.tf                     # Input variables
├── outputs.tf                       # Output values
├── terraform.tfvars                 # Environment-specific values (git-ignored)
├── versions.tf                      # Provider and version constraints
├── modules/
│   ├── gallery/
│   │   ├── main.tf                  # ACG + image definition
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── identity/
│   │   ├── main.tf                  # Managed identity + RBAC
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── image-builder/
│       ├── main.tf                  # AIB template + trigger (inline scripts)
│       ├── variables.tf
│       └── outputs.tf
```

---

## versions.tf

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }

  # Local backend — state is stored on the machine running terraform apply
  backend "local" {}
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azapi" {}
```

> **Why azapi?** The `azurerm` provider does not have full coverage for `Microsoft.VirtualMachineImages/imageTemplates` resources. The `azapi` provider gives direct ARM API access for the AIB template, which is the most reliable approach for defining customizers, distributor targets, and build VM configuration.

---

## variables.tf

```hcl
# ─── Subscription & Location ───────────────────────────────────────────────

variable "subscription_id" {
  description = "Azure subscription ID for all resources"
  type        = string
}

variable "location" {
  description = "Primary Azure region for all resources"
  type        = string
  default     = "eastus2"
}

# ─── Resource Group ────────────────────────────────────────────────────────

variable "resource_group_name" {
  description = "Resource group for image infrastructure"
  type        = string
  default     = "rg-w365-images"
}

# ─── Gallery ───────────────────────────────────────────────────────────────

variable "gallery_name" {
  description = "Azure Compute Gallery name (alphanumeric, no hyphens)"
  type        = string
  default     = "acgW365Dev"

  validation {
    condition     = can(regex("^[a-zA-Z0-9]+$", var.gallery_name))
    error_message = "Gallery name must be alphanumeric only (no hyphens or special characters)."
  }
}

variable "image_definition_name" {
  description = "Image definition name within the gallery (follows W365-W11-25H2-ENU naming convention)"
  type        = string
  default     = "W365-W11-25H2-ENU"
}

variable "image_publisher" {
  description = "Publisher identifier for the image definition"
  type        = string
  default     = "BigHatGroupInc"
}

variable "image_offer" {
  description = "Offer identifier for the image definition"
  type        = string
  default     = "W365-W11-25H2-ENU"
}

variable "image_sku" {
  description = "SKU identifier for the image definition"
  type        = string
  default     = "W11-25H2-ENT-Dev"
}

# ─── Image Version ─────────────────────────────────────────────────────────

variable "image_version" {
  description = "Semantic version for the image (Major.Minor.Patch)"
  type        = string
  default     = "1.0.0"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.image_version))
    error_message = "Image version must follow Major.Minor.Patch format (e.g., 1.0.0)."
  }
}

variable "exclude_from_latest" {
  description = "Set to true for canary/pilot versions; false for promoted production versions"
  type        = bool
  default     = true
}

variable "replica_count" {
  description = "Number of replicas per region"
  type        = number
  default     = 1
}

# ─── Build VM ──────────────────────────────────────────────────────────────

variable "build_vm_size" {
  description = "VM size for the AIB build VM"
  type        = string
  default     = "Standard_D4s_v5"
}

variable "build_timeout_minutes" {
  description = "Maximum build time in minutes"
  type        = number
  default     = 120
}

variable "os_disk_size_gb" {
  description = "OS disk size for the build VM in GB"
  type        = number
  default     = 128
}

# ─── Source Image ──────────────────────────────────────────────────────────

variable "source_image_publisher" {
  description = "Marketplace image publisher"
  type        = string
  default     = "MicrosoftWindowsDesktop"
}

variable "source_image_offer" {
  description = "Marketplace image offer"
  type        = string
  default     = "windows-11"
}

variable "source_image_sku" {
  description = "Marketplace image SKU"
  type        = string
  default     = "win11-24h2-ent"
}

variable "source_image_version" {
  description = "Marketplace image version — MUST be pinned to a specific version for build reproducibility (do not use 'latest')"
  type        = string
  default     = "26100.2894.250113"

  validation {
    condition     = var.source_image_version != "latest"
    error_message = "Source image version must be pinned to a specific version (not 'latest') for build reproducibility."
  }
}

# ─── Software Versions ────────────────────────────────────────────────────

variable "node_version" {
  description = "Node.js version to install (must be >= 22)"
  type        = string
  default     = "v24.13.1"

  validation {
    condition     = can(regex("^v(2[2-9]|[3-9][0-9])\\.\\d+\\.\\d+$", var.node_version))
    error_message = "Node.js version must be v22 or higher."
  }
}

variable "python_version" {
  description = "Python version to install"
  type        = string
  default     = "3.14.3"
}

variable "git_version" {
  description = "Git for Windows version to install"
  type        = string
  default     = "2.53.0"
}

variable "pwsh_version" {
  description = "PowerShell 7 (LTS) version to install"
  type        = string
  default     = "7.4.13"
}

variable "azure_cli_version" {
  description = "Azure CLI version to install"
  type        = string
  default     = "2.83.0"
}

variable "openclaw_version" {
  description = "OpenClaw npm package version to install"
  type        = string
  default     = "2026.2.14"
}

variable "claude_code_version" {
  description = "Claude Code (@anthropic-ai/claude-code) npm package version to install"
  type        = string
  default     = "2.1.42"
}

variable "openspec_version" {
  description = "OpenSpec (@fission-ai/openspec) npm package version to install"
  type        = string
  default     = "latest"
}

# ─── OpenClaw Configuration ───────────────────────────────────────────────

variable "openclaw_default_model" {
  description = "Default LLM model for OpenClaw configuration template"
  type        = string
  default     = "anthropic/claude-opus-4-6"
}

variable "openclaw_gateway_port" {
  description = "Port for the OpenClaw gateway"
  type        = number
  default     = 18789
}

# ─── Tags ──────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    workload   = "Windows365"
    purpose    = "DeveloperImages"
    managed_by = "PlatformEngineering"
    iac        = "Terraform"
  }
}
```

---

## modules/gallery/main.tf

```hcl
resource "azurerm_shared_image_gallery" "this" {
  name                = var.gallery_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_shared_image" "this" {
  name                = var.image_definition_name
  gallery_name        = azurerm_shared_image_gallery.this.name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Windows"
  hyper_v_generation  = "V2"
  architecture        = "x64"

  identifier {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
  }

  # ── Windows 365 ACG Import Requirements ──
  # All five features are mandatory for Windows 365 ingestion.
  # Missing any one will cause the import to fail.

  features {
    name  = "SecurityType"
    value = "TrustedLaunchSupported"
  }

  features {
    name  = "IsHibernateSupported"
    value = "True"
  }

  features {
    name  = "DiskControllerTypes"
    value = "SCSI,NVMe"
  }

  features {
    name  = "IsAcceleratedNetworkSupported"
    value = "True"
  }

  features {
    name  = "IsSecureBootSupported"
    value = "True"
  }

  tags = var.tags
}
```

---

## modules/identity/main.tf

```hcl
# ── User-Assigned Managed Identity for AIB ──
# AIB requires a managed identity to:
#   1. Read the source marketplace image
#   2. Write the output image version to the gallery
#   3. Create/manage the transient build VM and networking

resource "azurerm_user_assigned_identity" "aib" {
  name                = "id-aib-w365-dev"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# ── RBAC: Least-Privilege Roles ──
# Instead of broad Contributor access, assign only the specific roles
# that AIB requires to function.

# 1. Virtual Machine Contributor — allows AIB to create/manage the build VM
resource "azurerm_role_assignment" "aib_vm_contributor" {
  scope                = var.resource_group_id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_user_assigned_identity.aib.principal_id
}

# 2. Network Contributor — allows AIB to create transient networking for the build VM
resource "azurerm_role_assignment" "aib_network_contributor" {
  scope                = var.resource_group_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aib.principal_id
}

# 3. Managed Identity Operator — allows AIB to assign the identity to the build VM
resource "azurerm_role_assignment" "aib_identity_operator" {
  scope                = var.resource_group_id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.aib.principal_id
}

# 4. Compute Gallery Image Contributor — allows AIB to write image versions to the gallery
resource "azurerm_role_assignment" "aib_gallery_contributor" {
  scope                = var.gallery_id
  role_definition_name = "Compute Gallery Image Contributor"
  principal_id         = azurerm_user_assigned_identity.aib.principal_id
}
```

---

## modules/image-builder/main.tf

This is the core of the deployment. The AIB template is defined via the `azapi` provider because the `azurerm` provider lacks full `imageTemplates` resource support. All build scripts are inline — no external storage account is needed.

```hcl
locals {
  # Build a unique template name per version to allow parallel builds
  template_name = "aib-w365-dev-ai-${replace(var.image_version, ".", "-")}"

  # End-of-life date: 90 days from build
  end_of_life_date = timeadd(timestamp(), "2160h") # 90 days × 24 hours

  # ── Inline PowerShell Scripts ──
  # All scripts are embedded directly in the AIB template as inline
  # PowerShell customizers. No storage account is required.

  customizers = [
    # ── Phase 1: Core Runtimes (Node.js, Python, PowerShell 7) ──
    {
      type        = "PowerShell"
      name        = "InstallCoreRuntimes"
      runElevated = true
      runAsSystem = true
      inline = [
        <<-PWSH
        $ErrorActionPreference = "Stop"
        $ProgressPreference = "SilentlyContinue"

        function Update-SessionEnvironment {
            $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
            $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
            $env:Path = "$machinePath;$userPath"
            Write-Host "[PATH] Session environment refreshed"
        }

        function Get-InstallerWithRetry {
            param([string]$Uri, [string]$OutFile, [int]$MaxRetries = 3)
            for ($i = 1; $i -le $MaxRetries; $i++) {
                try {
                    Write-Host "[DOWNLOAD] Attempt $i of $MaxRetries : $Uri"
                    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
                    return
                } catch {
                    if ($i -eq $MaxRetries) { throw }
                    Write-Host "[DOWNLOAD] Attempt $i failed, retrying in 10 seconds..."
                    Start-Sleep -Seconds 10
                }
            }
        }

        # ═══ NODE.JS ═══
        $NodeVersion = "${var.node_version}"
        $NodeMsiUrl = "https://nodejs.org/dist/$NodeVersion/node-$NodeVersion-x64.msi"
        $NodeInstaller = "$env:TEMP\node-$NodeVersion-x64.msi"

        Write-Host "=== Installing Node.js $NodeVersion ==="
        Get-InstallerWithRetry -Uri $NodeMsiUrl -OutFile $NodeInstaller

        $proc = Start-Process -FilePath "msiexec.exe" `
            -ArgumentList "/i `"$NodeInstaller`" /qn /norestart ALLUSERS=1 ADDLOCAL=ALL" `
            -Wait -PassThru
        if ($proc.ExitCode -ne 0) { Write-Error "Node.js installation failed ($($proc.ExitCode))"; exit 1 }
        Update-SessionEnvironment
        Write-Host "[VERIFY] Node.js: $(node --version)"
        Write-Host "[VERIFY] npm: $(npm --version)"

        # ═══ PYTHON ═══
        $PythonVersion = "${var.python_version}"
        $PythonUrl = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe"
        $PythonInstaller = "$env:TEMP\python-$PythonVersion-amd64.exe"

        Write-Host "=== Installing Python $PythonVersion ==="
        Get-InstallerWithRetry -Uri $PythonUrl -OutFile $PythonInstaller

        $proc = Start-Process -FilePath $PythonInstaller `
            -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_pip=1 Include_test=0 Include_launcher=1" `
            -Wait -PassThru
        if ($proc.ExitCode -ne 0) { Write-Error "Python installation failed ($($proc.ExitCode))"; exit 1 }
        Update-SessionEnvironment
        Write-Host "[VERIFY] Python: $(python --version)"
        python -m pip install --upgrade pip --quiet
        Write-Host "[VERIFY] pip: $(python -m pip --version)"

        # ═══ POWERSHELL 7 ═══
        $PwshVersion = "${var.pwsh_version}"
        Write-Host "=== Installing PowerShell $PwshVersion ==="
        $PwshUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$PwshVersion/PowerShell-$PwshVersion-win-x64.msi"
        $PwshInstaller = "$env:TEMP\PowerShell-$PwshVersion-win-x64.msi"
        Get-InstallerWithRetry -Uri $PwshUrl -OutFile $PwshInstaller

        $proc = Start-Process -FilePath "msiexec.exe" `
            -ArgumentList "/i `"$PwshInstaller`" /qn /norestart ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=0 REGISTER_MANIFEST=1 USE_MU=0 ENABLE_MU=0 ADD_PATH=1" `
            -Wait -PassThru
        if ($proc.ExitCode -ne 0) { Write-Error "PowerShell 7 installation failed ($($proc.ExitCode))"; exit 1 }
        Update-SessionEnvironment
        Write-Host "[VERIFY] PowerShell 7 installed"

        # ═══ CLEANUP ═══
        Remove-Item -Path $NodeInstaller, $PythonInstaller, $PwshInstaller -Force -ErrorAction SilentlyContinue
        Write-Host "=== Phase 1 Complete: Runtimes installed ==="
        PWSH
      ]
    },
    # ── Restart after runtime installation ──
    {
      type              = "WindowsRestart"
      restartCommand    = "shutdown /r /f /t 5 /c \"Restart after runtime installation\""
      restartTimeout    = "10m"
      restartCheckCommand = "powershell -command \"node --version; python --version\""
    },
    # ── Phase 2: Developer Tools (VS Code, Git, GitHub Desktop) ──
    {
      type        = "PowerShell"
      name        = "InstallDevTools"
      runElevated = true
      runAsSystem = true
      inline = [
        <<-PWSH
        $ErrorActionPreference = "Stop"
        $ProgressPreference = "SilentlyContinue"

        function Update-SessionEnvironment {
            $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
            $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
            $env:Path = "$machinePath;$userPath"
        }

        function Get-InstallerWithRetry {
            param([string]$Uri, [string]$OutFile, [int]$MaxRetries = 3)
            for ($i = 1; $i -le $MaxRetries; $i++) {
                try { Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing; return }
                catch { if ($i -eq $MaxRetries) { throw }; Start-Sleep -Seconds 10 }
            }
        }

        # ═══ VISUAL STUDIO CODE ═══
        Write-Host "=== Installing Visual Studio Code (System) ==="
        $VSCodeUrl = "https://update.code.visualstudio.com/latest/win32-x64-system/stable"
        $VSCodeInstaller = "$env:TEMP\VSCodeSetup-x64.exe"
        Get-InstallerWithRetry -Uri $VSCodeUrl -OutFile $VSCodeInstaller

        $proc = Start-Process -FilePath $VSCodeInstaller `
            -ArgumentList "/VERYSILENT /NORESTART /MERGETASKS=`"!runcode,addcontextmenufiles,addcontextmenufolders,addtopath`"" `
            -Wait -PassThru
        if ($proc.ExitCode -ne 0) { Write-Error "VS Code installation failed ($($proc.ExitCode))"; exit 1 }
        Update-SessionEnvironment
        Write-Host "[VERIFY] VS Code installed to: C:\Program Files\Microsoft VS Code"

        # ═══ GIT FOR WINDOWS ═══
        Write-Host "=== Installing Git for Windows ==="
        $GitVersion = "${var.git_version}"
        $GitUrl = "https://github.com/git-for-windows/git/releases/download/v$${GitVersion}.windows.1/Git-$${GitVersion}-64-bit.exe"
        $GitInstaller = "$env:TEMP\Git-$${GitVersion}-64-bit.exe"
        Get-InstallerWithRetry -Uri $GitUrl -OutFile $GitInstaller

        $proc = Start-Process -FilePath $GitInstaller `
            -ArgumentList "/VERYSILENT /NORESTART /PathOption=Cmd /NoAutoCrlf /SetupType=default" `
            -Wait -PassThru
        if ($proc.ExitCode -ne 0) { Write-Error "Git installation failed ($($proc.ExitCode))"; exit 1 }
        Update-SessionEnvironment
        Write-Host "[VERIFY] Git: $(git --version)"

        # ═══ GITHUB DESKTOP ═══
        Write-Host "=== Installing GitHub Desktop (Machine-Wide Provisioner) ==="
        $GHDesktopUrl = "https://central.github.com/deployments/desktop/desktop/latest/GitHubDesktopSetup-x64.msi"
        $GHDesktopInstaller = "$env:TEMP\GitHubDesktop-x64.msi"
        Get-InstallerWithRetry -Uri $GHDesktopUrl -OutFile $GHDesktopInstaller

        $proc = Start-Process -FilePath "msiexec.exe" `
            -ArgumentList "/i `"$GHDesktopInstaller`" /qn /norestart ALLUSERS=1" `
            -Wait -PassThru
        if ($proc.ExitCode -ne 0) { Write-Error "GitHub Desktop installation failed ($($proc.ExitCode))"; exit 1 }
        Write-Host "[VERIFY] GitHub Desktop provisioner installed"

        # ═══ AZURE CLI ═══
        $AzCliVersion = "${var.azure_cli_version}"
        Write-Host "=== Installing Azure CLI $AzCliVersion ==="
        $AzCliUrl = "https://azcliprod.blob.core.windows.net/msi/azure-cli-$AzCliVersion-x64.msi"
        $AzCliInstaller = "$env:TEMP\azure-cli-$AzCliVersion-x64.msi"
        Get-InstallerWithRetry -Uri $AzCliUrl -OutFile $AzCliInstaller

        $proc = Start-Process -FilePath "msiexec.exe" `
            -ArgumentList "/i `"$AzCliInstaller`" /qn /norestart ALLUSERS=1" `
            -Wait -PassThru
        if ($proc.ExitCode -ne 0) { Write-Error "Azure CLI installation failed ($($proc.ExitCode))"; exit 1 }
        Update-SessionEnvironment
        Write-Host "[VERIFY] Azure CLI: $(az --version 2>&1 | Select-Object -First 1)"

        # ═══ CLEANUP ═══
        Remove-Item -Path $VSCodeInstaller, $GitInstaller, $GHDesktopInstaller, $AzCliInstaller -Force -ErrorAction SilentlyContinue
        Write-Host "=== Phase 2 Complete: Developer tools installed ==="
        PWSH
      ]
    },
    # ── Phase 3: AI Agents (OpenClaw + Claude Code + OpenSpec) ──
    {
      type        = "PowerShell"
      name        = "InstallAIAgents"
      runElevated = true
      runAsSystem = true
      inline = [
        <<-PWSH
        $ErrorActionPreference = "Stop"
        $ProgressPreference = "SilentlyContinue"

        function Update-SessionEnvironment {
            $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
            $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
            $env:Path = "$machinePath;$userPath"
        }

        Update-SessionEnvironment

        # Verify prerequisites
        $nodeCheck = Get-Command node -ErrorAction SilentlyContinue
        $npmCheck = Get-Command npm -ErrorAction SilentlyContinue
        if (-not $nodeCheck -or -not $npmCheck) {
            Write-Error "Node.js or npm not found in PATH. Phase 1 may have failed."
            exit 1
        }
        Write-Host "[PREREQ] Node.js: $(node --version)"
        Write-Host "[PREREQ] npm: $(npm --version)"

        # ═══ NPM AUDIT: Pre-installation security check ═══
        # Audit will be run after installation to catch vulnerabilities

        # ═══ OPENCLAW ═══
        Write-Host "=== Installing OpenClaw ${var.openclaw_version} (global) ==="
        npm install -g openclaw@${var.openclaw_version} 2>&1 | Write-Host
        if ($LASTEXITCODE -ne 0) { Write-Error "OpenClaw npm install failed ($LASTEXITCODE)"; exit 1 }
        Update-SessionEnvironment

        $openclawCheck = Get-Command openclaw -ErrorAction SilentlyContinue
        if (-not $openclawCheck) { Write-Error "openclaw not found in PATH after installation"; exit 1 }
        Write-Host "[VERIFY] OpenClaw: $(openclaw --version 2>&1)"

        # ═══ CLAUDE CODE ═══
        Write-Host "=== Installing Claude Code ${var.claude_code_version} (global) ==="
        npm install -g @anthropic-ai/claude-code@${var.claude_code_version} 2>&1 | Write-Host
        if ($LASTEXITCODE -ne 0) { Write-Error "Claude Code npm install failed ($LASTEXITCODE)"; exit 1 }
        Update-SessionEnvironment

        $claudeCheck = Get-Command claude -ErrorAction SilentlyContinue
        if (-not $claudeCheck) { Write-Error "claude not found in PATH after installation"; exit 1 }
        Write-Host "[VERIFY] Claude Code: $(claude --version 2>&1)"

        # ═══ OPENSPEC ═══
        Write-Host "=== Installing OpenSpec ${var.openspec_version} (global) ==="
        npm install -g @fission-ai/openspec@${var.openspec_version} 2>&1 | Write-Host
        if ($LASTEXITCODE -ne 0) { Write-Error "OpenSpec npm install failed ($LASTEXITCODE)"; exit 1 }
        Update-SessionEnvironment

        $openspecCheck = Get-Command openspec -ErrorAction SilentlyContinue
        if (-not $openspecCheck) { Write-Error "openspec not found in PATH after installation"; exit 1 }
        Write-Host "[VERIFY] OpenSpec: $(openspec --version 2>&1)"

        # ═══ NPM AUDIT ═══
        Write-Host "=== Running npm audit on global packages ==="
        $auditResult = npm audit --global --audit-level=high 2>&1
        Write-Host $auditResult
        if ($LASTEXITCODE -ne 0) {
            Write-Error "npm audit found high/critical vulnerabilities. Failing build."
            exit 1
        }
        Write-Host "[SECURITY] npm audit passed — no high/critical vulnerabilities"

        # ═══ SBOM GENERATION ═══
        Write-Host "=== Generating Software Bill of Materials (SBOM) ==="
        $sbomDir = "C:\ProgramData\ImageBuild"
        New-Item -ItemType Directory -Path $sbomDir -Force | Out-Null

        $globalPackages = npm list -g --json 2>$null
        Set-Content -Path "$sbomDir\sbom-npm-global.json" -Value $globalPackages -Encoding UTF8
        Write-Host "[SBOM] npm global packages: $sbomDir\sbom-npm-global.json"

        # Record installed software versions
        $softwareManifest = @{
            buildDate       = (Get-Date -Format "yyyy-MM-dd'T'HH:mm:ss'Z'")
            nodeVersion     = (node --version 2>&1).ToString()
            npmVersion      = (npm --version 2>&1).ToString()
            pythonVersion   = (python --version 2>&1).ToString()
            gitVersion      = (git --version 2>&1).ToString()
            pwshVersion     = (pwsh --version 2>&1).ToString()
            azCliVersion    = (az --version 2>&1 | Select-Object -First 1).ToString()
            openclawVersion = (openclaw --version 2>&1).ToString()
            claudeVersion   = (claude --version 2>&1).ToString()
            openspecVersion = (openspec --version 2>&1).ToString()
        } | ConvertTo-Json -Depth 3
        Set-Content -Path "$sbomDir\sbom-software-manifest.json" -Value $softwareManifest -Encoding UTF8
        Write-Host "[SBOM] Software manifest: $sbomDir\sbom-software-manifest.json"

        Write-Host "=== Phase 3 Complete: AI agents installed ==="
        PWSH
      ]
    },
    # ── Phase 4: Configuration & Policy ──
    {
      type        = "PowerShell"
      name        = "ConfigureAgents"
      runElevated = true
      runAsSystem = true
      inline = [
        <<-PWSH
        $ErrorActionPreference = "Stop"

        # ═══ CLAUDE CODE: Enterprise Managed Settings ═══
        Write-Host "=== Configuring Claude Code enterprise policy ==="
        $claudeConfigDir = "C:\ProgramData\ClaudeCode"
        New-Item -ItemType Directory -Path $claudeConfigDir -Force | Out-Null

        $managedSettings = @{
            autoUpdatesChannel = "stable"
            permissions = @{
                defaultMode = "allow"
            }
        } | ConvertTo-Json -Depth 5

        $managedSettingsPath = "$claudeConfigDir\managed-settings.json"
        Set-Content -Path $managedSettingsPath -Value $managedSettings -Encoding UTF8
        Write-Host "[CONFIG] Claude Code managed settings: $managedSettingsPath"

        # ═══ OPENCLAW: Configuration Template ═══
        Write-Host "=== Creating OpenClaw configuration template ==="
        $openclawTemplateDir = "C:\ProgramData\OpenClaw"
        New-Item -ItemType Directory -Path $openclawTemplateDir -Force | Out-Null

        $openclawConfig = @{
            agent = @{
                model = "${var.openclaw_default_model}"
                defaults = @{
                    workspace = "~/Documents/OpenClawWorkspace"
                }
            }
            gateway = @{
                mode = "local"
                port = ${var.openclaw_gateway_port}
            }
            channels = @{
                web = @{ enabled = $true }
            }
        } | ConvertTo-Json -Depth 5

        $templatePath = "$openclawTemplateDir\template-config.json"
        Set-Content -Path $templatePath -Value $openclawConfig -Encoding UTF8
        Write-Host "[CONFIG] OpenClaw template: $templatePath"

        # ═══ ACTIVE SETUP: First-Login Configuration Hydration ═══
        Write-Host "=== Registering Active Setup for first-login hydration ==="

        # Hydration script OVERWRITES existing config to ensure consistency
        $hydrationScript = @'
$openclawDir = "$env:USERPROFILE\.openclaw"
$configFile = "$openclawDir\openclaw.json"
$templateFile = "C:\ProgramData\OpenClaw\template-config.json"

if (Test-Path $templateFile) {
    New-Item -ItemType Directory -Path $openclawDir -Force | Out-Null
    $workspaceDir = "$env:USERPROFILE\Documents\OpenClawWorkspace"
    New-Item -ItemType Directory -Path $workspaceDir -Force | Out-Null
    Copy-Item -Path $templateFile -Destination $configFile -Force
}
'@

        $hydrationScriptPath = "$openclawTemplateDir\hydrate-config.ps1"
        Set-Content -Path $hydrationScriptPath -Value $hydrationScript -Encoding UTF8

        # Register via Active Setup
        $activeSetupKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\OpenClaw-ConfigHydration"
        New-Item -Path $activeSetupKey -Force | Out-Null
        Set-ItemProperty -Path $activeSetupKey -Name "(Default)" -Value "OpenClaw Configuration Hydration"
        Set-ItemProperty -Path $activeSetupKey -Name "StubPath" -Value "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$hydrationScriptPath`""
        Set-ItemProperty -Path $activeSetupKey -Name "Version" -Value "1,0,0,0"
        Write-Host "[CONFIG] Active Setup registered: OpenClaw-ConfigHydration"

        # ═══ TEAMS OPTIMISATION PREREQUISITES ═══
        Write-Host "=== Setting Teams optimisation prerequisites ==="
        $teamsRegPath = "HKLM:\SOFTWARE\Microsoft\Teams"
        if (-not (Test-Path $teamsRegPath)) {
            New-Item -Path $teamsRegPath -Force | Out-Null
        }
        Set-ItemProperty -Path $teamsRegPath -Name "IsWVDEnvironment" -Value 1 -Type DWord -Force
        Write-Host "[CONFIG] Teams IsWVDEnvironment = 1"

        # ═══ IMAGE CLEANUP & OPTIMISATION ═══
        Write-Host "=== Cleaning up image ==="
        Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        npm cache clean --force 2>&1 | Out-Null

        Write-Host "[CLEANUP] Running DISM component store cleanup..."
        Start-Process -FilePath "dism.exe" `
            -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /ResetBase" `
            -Wait -NoNewWindow

        Write-Host "=== Phase 4 Complete: Configuration and cleanup done ==="
        PWSH
      ]
    },
    # ── Windows Update ──
    {
      type = "WindowsUpdate"
      searchCriteria = "IsInstalled=0"
      filters = [
        "exclude:$_.Title -like '*Preview*'",
        "include:$true"
      ]
      updateLimit = 40
    },
    # ── Final Restart ──
    {
      type           = "WindowsRestart"
      restartTimeout = "10m"
    }
  ]

  # Distributor: publish to Azure Compute Gallery
  distribute = [
    {
      type               = "SharedImage"
      galleryImageId     = var.image_definition_id
      runOutputName      = "w365-dev-ai-${var.image_version}"
      excludeFromLatest  = var.exclude_from_latest
      replicationRegions = [var.location]
      storageAccountType = "Standard_LRS"
      versioning = {
        scheme = "Latest"
        major  = tonumber(split(".", var.image_version)[0])
      }
      endOfLifeDate = local.end_of_life_date
      replicaCount  = var.replica_count
    }
  ]

  # Build VM profile
  vm_profile = {
    vmSize       = var.build_vm_size
    osDiskSizeGB = var.os_disk_size_gb
  }
}

# ── AIB Image Template ──
resource "azapi_resource" "image_template" {
  type      = "Microsoft.VirtualMachineImages/imageTemplates@2024-02-01"
  name      = local.template_name
  location  = var.location
  parent_id = var.resource_group_id

  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  tags = var.tags

  body = {
    properties = {
      buildTimeoutInMinutes = var.build_timeout_minutes

      source = {
        type      = "PlatformImage"
        publisher = var.source_image_publisher
        offer     = var.source_image_offer
        sku       = var.source_image_sku
        version   = var.source_image_version
      }

      customize = local.customizers

      distribute = local.distribute

      vmProfile = local.vm_profile
    }
  }
}

# ── Trigger the Build ──
resource "azapi_resource_action" "run_build" {
  type        = "Microsoft.VirtualMachineImages/imageTemplates@2024-02-01"
  resource_id = azapi_resource.image_template.id
  action      = "run"

  depends_on = [azapi_resource.image_template]

  timeouts {
    create = "${var.build_timeout_minutes + 30}m"
  }
}
```

---

## main.tf (Root Module)

```hcl
resource "azurerm_resource_group" "images" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ── Azure Compute Gallery ──
module "gallery" {
  source = "./modules/gallery"

  resource_group_name   = azurerm_resource_group.images.name
  location              = var.location
  gallery_name          = var.gallery_name
  image_definition_name = var.image_definition_name
  image_publisher       = var.image_publisher
  image_offer           = var.image_offer
  image_sku             = var.image_sku
  tags                  = var.tags
}

# ── Managed Identity + RBAC ──
module "identity" {
  source = "./modules/identity"

  resource_group_name = azurerm_resource_group.images.name
  resource_group_id   = azurerm_resource_group.images.id
  location            = var.location
  gallery_id          = module.gallery.gallery_id
  tags                = var.tags
}

# ── Image Builder ──
module "image_builder" {
  source = "./modules/image-builder"

  resource_group_id      = azurerm_resource_group.images.id
  location               = var.location
  managed_identity_id    = module.identity.managed_identity_id
  image_definition_id    = module.gallery.image_definition_id
  image_version          = var.image_version
  exclude_from_latest    = var.exclude_from_latest
  replica_count          = var.replica_count
  build_vm_size          = var.build_vm_size
  build_timeout_minutes  = var.build_timeout_minutes
  os_disk_size_gb        = var.os_disk_size_gb
  source_image_publisher = var.source_image_publisher
  source_image_offer     = var.source_image_offer
  source_image_sku       = var.source_image_sku
  source_image_version   = var.source_image_version
  node_version           = var.node_version
  python_version         = var.python_version
  git_version            = var.git_version
  pwsh_version           = var.pwsh_version
  azure_cli_version      = var.azure_cli_version
  openclaw_version       = var.openclaw_version
  claude_code_version    = var.claude_code_version
  openspec_version       = var.openspec_version
  openclaw_default_model = var.openclaw_default_model
  openclaw_gateway_port  = var.openclaw_gateway_port
  tags                   = var.tags
}
```

---

## outputs.tf

```hcl
output "gallery_id" {
  description = "Azure Compute Gallery resource ID"
  value       = module.gallery.gallery_id
}

output "image_definition_id" {
  description = "Image definition resource ID"
  value       = module.gallery.image_definition_id
}

output "managed_identity_id" {
  description = "AIB managed identity resource ID"
  value       = module.identity.managed_identity_id
}

output "managed_identity_principal_id" {
  description = "AIB managed identity principal ID (for additional RBAC)"
  value       = module.identity.managed_identity_principal_id
}

output "image_template_name" {
  description = "AIB image template name"
  value       = module.image_builder.template_name
}

output "next_steps" {
  description = "Manual steps required after Terraform apply"
  value       = <<-EOT

    ══════════════════════════════════════════════════════════════════
    IMAGE BUILD COMPLETE — NEXT STEPS
    ══════════════════════════════════════════════════════════════════

    1. VERIFY IMAGE VERSION
       Get-AzGalleryImageVersion `
         -ResourceGroupName "${var.resource_group_name}" `
         -GalleryName "${var.gallery_name}" `
         -GalleryImageDefinitionName "${var.image_definition_name}" |
         Format-Table Name, ProvisioningState, PublishingProfile

    2. TEAR DOWN BUILD INFRASTRUCTURE (cost optimization)
       Keep only the gallery and image — destroy everything else:
       terraform destroy

       NOTE: The image version persists in the gallery independently
       of the AIB template and other build resources.

    3. IMPORT INTO WINDOWS 365 (Portal)
       Intune > Devices > Windows 365 > Custom images > Add
       > Azure Compute Gallery
       > Select: ${var.gallery_name} / ${var.image_definition_name} / ${var.image_version}

    4. CREATE/UPDATE PROVISIONING POLICY
       Assign the imported image to a provisioning policy
       targeting your developer security group.

    5. USER CONFIGURATION (post-login)
       Each user manages their own ANTHROPIC_API_KEY:
       - Set as user environment variable, or
       - Configure via OpenClaw settings

    6. PROMOTE (when validated)
       Set exclude_from_latest = false and re-apply:
       terraform apply -var="exclude_from_latest=false"

    ══════════════════════════════════════════════════════════════════
  EOT
}
```

---

## terraform.tfvars (Example)

```hcl
# ── Environment-Specific Values ──
# Copy this file and adjust for your environment.
# Do NOT commit secrets to source control.

subscription_id       = "00000000-0000-0000-0000-000000000000"
location              = "eastus2"
resource_group_name   = "rg-w365-images"

# Gallery
gallery_name          = "acgW365Dev"
image_definition_name = "W365-W11-25H2-ENU"
image_publisher       = "BigHatGroupInc"
image_offer           = "W365-W11-25H2-ENU"
image_sku             = "W11-25H2-ENT-Dev"

# Image Version
image_version         = "1.0.0"
exclude_from_latest   = true     # Set to false after pilot validation
replica_count         = 1

# Build VM
build_vm_size         = "Standard_D4s_v5"
build_timeout_minutes = 120
os_disk_size_gb       = 128

# Source Image (pinned for reproducibility)
source_image_publisher = "MicrosoftWindowsDesktop"
source_image_offer     = "windows-11"
source_image_sku       = "win11-24h2-ent"
source_image_version   = "26100.2894.250113"

# Software Versions (pinned)
node_version          = "v24.13.1"
python_version        = "3.14.3"
git_version           = "2.53.0"
pwsh_version          = "7.4.13"
azure_cli_version     = "2.83.0"
openclaw_version      = "2026.2.14"
claude_code_version   = "2.1.42"
openspec_version      = "latest"

# OpenClaw
openclaw_default_model = "anthropic/claude-opus-4-6"
openclaw_gateway_port  = 18789

# Tags
tags = {
  workload    = "Windows365"
  purpose     = "DeveloperImages"
  managed_by  = "PlatformEngineering"
  iac         = "Terraform"
  cost_center = "Engineering"
}
```

---

## Operational Runbook

### First Deployment

```powershell
Set-Location terraform

# Initialise (local backend — no remote state configuration needed)
terraform init

# Plan
terraform plan -var-file="terraform.tfvars" -out tfplan

# Apply (deploys infra + triggers image build)
terraform apply tfplan

# After build completes and image is verified, tear down build resources
terraform destroy
```

### Version Bump (New Image Build)

```powershell
# Increment the version and build
terraform apply `
  -var='image_version=1.1.0' `
  -var='exclude_from_latest=true'

# After pilot validation, promote
terraform apply `
  -var='image_version=1.1.0' `
  -var='exclude_from_latest=false'

# Tear down build resources
terraform destroy
```

### Hotfix

```powershell
terraform apply `
  -var='image_version=1.0.1' `
  -var='exclude_from_latest=false'

# Tear down build resources
terraform destroy
```

### Version Retention Cleanup

Retain only the 3 most recent image versions. Remove older versions to reduce storage costs:

```powershell
# List all versions
Get-AzGalleryImageVersion `
  -ResourceGroupName "rg-w365-images" `
  -GalleryName "acgW365Dev" `
  -GalleryImageDefinitionName "W365-W11-25H2-ENU" |
  Format-Table Name, ProvisioningState, PublishingProfile

# Delete a specific old version
Remove-AzGalleryImageVersion `
  -ResourceGroupName "rg-w365-images" `
  -GalleryName "acgW365Dev" `
  -GalleryImageDefinitionName "W365-W11-25H2-ENU" `
  -Name "1.0.0" `
  -Force
```

---

## Security Considerations

| Risk | Mitigation |
|---|---|
| API keys baked into image | Never. Each user manages their own ANTHROPIC_API_KEY after login. |
| AI agent runs as SYSTEM | OpenClaw runs in user context (Active Setup + user-level startup). Do not register as a SYSTEM service. |
| Supply chain (npm packages) | Pinned to specific versions (`openclaw@${var.openclaw_version}`, `@anthropic-ai/claude-code@${var.claude_code_version}`, `openspec@${var.openspec_version}`). npm audit runs during build and fails on high/critical vulnerabilities. |
| SBOM | Software Bill of Materials generated during build and stored at `C:\ProgramData\ImageBuild\sbom-*.json`. |
| Build script integrity | Scripts are inline in the Terraform configuration — no external storage dependencies. Changes are tracked via source control. |
| Image sprawl / cost | `end_of_life_date` set to 90 days from build. Retain only 3 versions. Tear down build infrastructure after each build. |
| Credential storage at runtime | OpenClaw stores config in `~/.openclaw` (plaintext JSON). Cloud PC disks are encrypted at rest (Azure SSE, 256-bit AES). |

---

## Validation Checklist

After the image build completes and before importing into Windows 365:

- [ ] Image version appears in ACG with correct replication status
- [ ] `node --version` returns v24+ (test by creating a VM from the image)
- [ ] `python --version` returns 3.14+
- [ ] `pwsh --version` returns PowerShell 7.4+
- [ ] `git --version` returns expected version
- [ ] `az --version` returns expected Azure CLI version
- [ ] `openclaw --version` returns expected version
- [ ] `claude --version` returns expected version
- [ ] `openspec --version` returns expected version
- [ ] VS Code installed in `C:\Program Files\Microsoft VS Code`
- [ ] `C:\ProgramData\ClaudeCode\managed-settings.json` exists with `defaultMode: "allow"`
- [ ] `C:\ProgramData\OpenClaw\template-config.json` exists with model `claude-opus-4-6`
- [ ] Active Setup registry key exists for OpenClaw config hydration
- [ ] Teams `IsWVDEnvironment` registry key is set to 1
- [ ] SBOM files exist in `C:\ProgramData\ImageBuild\`
- [ ] npm audit passed (no high/critical vulnerabilities)
- [ ] No recovery partition present
- [ ] Image is generalised (Sysprep completed successfully)
- [ ] Image was never Entra/AD joined or Intune enrolled
- [ ] `end_of_life_date` is set to 90 days from build date

After Windows 365 provisioning:

- [ ] Cloud PC provisions successfully from the image
- [ ] Developer can sign in and see OpenClaw config hydrated in `~/.openclaw/`
- [ ] Config is overwritten on each login (Active Setup version bump forces refresh)
- [ ] `claude` CLI works after user configures their own API key
- [ ] GitHub Desktop hydrates on first login
- [ ] Teams media optimisation is active

---

*This specification is a companion to [Building an OpenClaw and Claude Code Developer Image for Windows 365 Using Azure Compute Gallery](./BuildingOpenClawforWindows365UsingAzureComputeGallery.md). Refer to the blog article for architectural rationale, the reprovisioning model, and detailed discussion of design decisions.*
