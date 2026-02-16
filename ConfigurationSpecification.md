# Configuration Specification: Build Workstation Prerequisites

> Requirements for preparing a Windows workstation to execute the W365Claw Terraform solution. This document feeds into an OpenSpec proposal that automates prerequisite installation and validation via PowerShell.

---

## Purpose

Before an operator can run `terraform apply` to build a Windows 365 developer image, their workstation must have specific tooling installed, Azure authentication configured, and Azure resource providers registered. Today this is manual and undocumented — leading to failed builds, missing providers, and wasted troubleshooting time.

This specification defines everything needed so that a single PowerShell script (or OpenSpec change) can take a clean Windows machine to "ready to build" state.

---

## Target Environment

| Attribute | Value |
|-----------|-------|
| **OS** | Windows 10/11 (x64) |
| **Shell** | PowerShell 5.1+ (Windows PowerShell) and/or PowerShell 7+ |
| **Privileges** | Administrator (for software installation) |
| **Network** | Internet access (to download installers, authenticate to Azure, pull Terraform providers) |

---

## 1. Software Prerequisites

### 1.1 Terraform CLI

| Attribute | Requirement |
|-----------|-------------|
| **Minimum version** | >= 1.5.0 |
| **Installation method** | Official HashiCorp release (ZIP extract to PATH) or `winget install Hashicorp.Terraform` |
| **PATH** | `terraform.exe` must be resolvable from PowerShell |
| **Verification** | `terraform version` returns >= 1.5.0 |

**Notes:**
- Do NOT use Chocolatey — `winget` is the preferred Windows package manager
- If `winget` is unavailable, download the ZIP from https://releases.hashicorp.com/terraform/ and extract to a directory on PATH (e.g., `C:\Tools\Terraform`)

### 1.2 Azure PowerShell Module (Az)

| Attribute | Requirement |
|-----------|-------------|
| **Module** | `Az` (meta-module) |
| **Minimum version** | >= 12.0 |
| **Required sub-modules** | `Az.Accounts`, `Az.Compute`, `Az.Resources`, `Az.ManagedServiceIdentity`, `Az.ImageBuilder` |
| **Installation** | `Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force` |
| **Verification** | `Get-Module -ListAvailable Az` returns >= 12.0 |

**Notes:**
- Used for post-build verification (`Get-AzGalleryImageVersion`), image promotion, and version cleanup — NOT for the Terraform build itself
- If running in PowerShell 7, ensure PSGallery is trusted: `Set-PSRepository -Name PSGallery -InstallationPolicy Trusted`

### 1.3 Git

| Attribute | Requirement |
|-----------|-------------|
| **Minimum version** | >= 2.40 |
| **Installation method** | `winget install Git.Git` or existing installation |
| **PATH** | `git.exe` must be resolvable from PowerShell |
| **Verification** | `git --version` returns >= 2.40 |

**Notes:**
- Required for cloning the W365Claw repository and committing changes
- Likely already installed on developer workstations

### 1.4 Node.js (Optional)

| Attribute | Requirement |
|-----------|-------------|
| **Minimum version** | >= 22 |
| **When required** | Only if the operator needs to run OpenSpec CLI locally |
| **Installation method** | `winget install OpenJS.NodeJS.LTS` |
| **Verification** | `node --version` returns >= v22 |

---

## 2. Azure Authentication

### 2.1 Azure Account Login

| Attribute | Requirement |
|-----------|-------------|
| **Method** | Interactive browser login via `Connect-AzAccount` or `az login` equivalent |
| **Terraform auth** | Terraform AzureRM provider authenticates via Azure CLI token cache or environment variables |
| **Subscription** | The target subscription must be set as the active context |

**Authentication flow for Terraform:**

Terraform uses the Azure CLI credential chain by default. The operator must either:

1. **Azure CLI** (preferred for Terraform): Install Azure CLI and run `az login`, then `az account set --subscription <id>`
2. **Environment variables**: Set `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID`, `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET` (for service principal auth — CI/CD use case, out of scope for manual builds)

### 2.2 Azure CLI

| Attribute | Requirement |
|-----------|-------------|
| **Minimum version** | >= 2.60 |
| **Installation method** | `winget install Microsoft.AzureCLI` |
| **PATH** | `az.exe` or `az.cmd` must be resolvable |
| **Verification** | `az version` returns >= 2.60 |

**Notes:**
- Yes, the project convention says "PowerShell everywhere, no Azure CLI" for **scripts and documentation** — but Terraform's AzureRM provider uses the Azure CLI token cache for authentication. The CLI is needed as an auth mechanism, not as a scripting tool.
- After install: `az login` then `az account set --subscription "<subscription_id>"`

### 2.3 Required Azure Permissions

The operator's Azure account (or service principal) must have:

| Permission | Scope | Purpose |
|------------|-------|---------|
| **Contributor** | Subscription or Resource Group | Create resource group, gallery, identity, AIB template |
| **User Access Administrator** | Resource Group | Create RBAC role assignments for the managed identity |
| **Resource Provider registration** | Subscription | Register required resource providers (if not already) |

**Minimum viable alternative:** `Owner` on the target resource group (combines Contributor + User Access Administrator). If the resource group doesn't exist yet, the operator needs Contributor at subscription scope to create it.

---

## 3. Azure Resource Provider Registration

The following resource providers must be registered on the target subscription before `terraform apply`:

| Resource Provider | Purpose | Registration |
|-------------------|---------|--------------|
| `Microsoft.Compute` | Azure Compute Gallery, image definitions, image versions | Usually registered by default |
| `Microsoft.VirtualMachineImages` | Azure VM Image Builder | **Often NOT registered by default** — must be explicitly registered |
| `Microsoft.Network` | Transient networking for AIB build VM | Usually registered by default |
| `Microsoft.ManagedIdentity` | User-assigned managed identity | Usually registered by default |

**Registration commands:**

```powershell
# Check current registration status
Get-AzResourceProvider -ProviderNamespace Microsoft.VirtualMachineImages |
  Select-Object ProviderNamespace, RegistrationState

# Register if needed
Register-AzResourceProvider -ProviderNamespace Microsoft.VirtualMachineImages

# Verify (may take 1-2 minutes)
while ((Get-AzResourceProvider -ProviderNamespace Microsoft.VirtualMachineImages).RegistrationState -ne "Registered") {
    Write-Host "Waiting for Microsoft.VirtualMachineImages registration..."
    Start-Sleep -Seconds 10
}
```

Or via Azure CLI:

```powershell
az provider register --namespace Microsoft.VirtualMachineImages
az provider show --namespace Microsoft.VirtualMachineImages --query "registrationState"
```

---

## 4. Repository Setup

### 4.1 Clone the Repository

```powershell
git clone https://github.com/<org>/W365Claw.git
Set-Location W365Claw\terraform
```

### 4.2 Configure terraform.tfvars

The operator must create or update `terraform/terraform.tfvars` with their environment-specific values:

| Variable | Required | Description |
|----------|----------|-------------|
| `subscription_id` | **Yes** | Target Azure subscription ID |
| `location` | No | Azure region (default: `eastus2`) |
| `resource_group_name` | No | Resource group name (default: `rg-w365-images`) |
| `image_version` | **Yes** (for each build) | Semantic version for the image (e.g., `1.0.0`) |

All other variables have sensible defaults. The operator should review `terraform.tfvars` and adjust software versions if needed.

### 4.3 Terraform Initialization

```powershell
terraform init
```

This downloads the required providers (`azurerm`, `azapi`, `time`) and initializes the local backend. Must be run once per clone, or after provider version changes.

---

## 5. Validation Script Requirements

The OpenSpec proposal should produce a PowerShell script that:

### 5.1 Pre-Flight Checks (Non-Destructive)

1. **Check OS**: Confirm Windows 10/11 x64
2. **Check admin**: Confirm running as Administrator
3. **Check each tool**: Terraform, Azure CLI, Git, Az PowerShell module — report installed version or "MISSING"
4. **Check Azure login**: `az account show` succeeds and subscription is set
5. **Check resource providers**: All four providers registered
6. **Check terraform init**: `terraform init` has been run (`.terraform/` directory exists)

Output a summary table:

```
╔══════════════════════════════════════════════════════╗
║           W365Claw Build Prerequisites               ║
╠══════════════════════════════════════════════════════╣
║ Terraform      │ ✅ 1.9.5 (>= 1.5.0)               ║
║ Azure CLI      │ ✅ 2.67.0 (>= 2.60)               ║
║ Git            │ ✅ 2.53.0 (>= 2.40)               ║
║ Az Module      │ ❌ NOT INSTALLED                    ║
║ Azure Login    │ ✅ Subscription: rg-w365-images     ║
║ RP: Compute    │ ✅ Registered                       ║
║ RP: VMImages   │ ❌ NotRegistered                    ║
║ RP: Network    │ ✅ Registered                       ║
║ RP: ManagedId  │ ✅ Registered                       ║
║ terraform init │ ✅ Initialized                      ║
╚══════════════════════════════════════════════════════╝
```

### 5.2 Installation (Interactive, with Confirmation)

For each missing prerequisite, prompt the operator and install:

1. **Terraform**: `winget install Hashicorp.Terraform` (fall back to ZIP download if winget unavailable)
2. **Azure CLI**: `winget install Microsoft.AzureCLI`
3. **Git**: `winget install Git.Git`
4. **Az Module**: `Install-Module -Name Az -Scope CurrentUser -Force`
5. **Azure login**: Launch `az login` if not authenticated
6. **Resource providers**: Register any unregistered providers (with wait loop)
7. **Terraform init**: Run `terraform init` if `.terraform/` doesn't exist

### 5.3 Post-Installation Verification

Re-run all pre-flight checks and confirm everything passes. Exit with:
- **Exit code 0**: All prerequisites met
- **Exit code 1**: One or more prerequisites could not be installed/configured (with details)

---

## 6. Idempotency Requirements

The script MUST be idempotent:
- Running it on an already-configured machine should be a no-op (all checks pass, nothing installed)
- Running it after a partial failure should pick up where it left off
- It should never downgrade existing software
- It should never re-register already-registered resource providers

---

## 7. Out of Scope

| Item | Reason |
|------|--------|
| **CI/CD service principal setup** | Manual builds only — operator uses their own Azure identity |
| **Terraform remote backend** | Solution uses local backend per spec |
| **VPN/network configuration** | Assumed to be handled by corporate IT |
| **VS Code extensions** | Developer preference — not a build prerequisite |
| **Intune/MDM enrollment** | Post-provisioning concern |
| **ANTHROPIC_API_KEY** | Per-user post-login configuration |

---

## 8. OpenSpec Proposal Scope

The resulting OpenSpec change should:

1. **Create a PowerShell script** (`scripts/Initialize-BuildWorkstation.ps1`) that implements sections 5.1–5.3
2. **Update README.md** with a "Getting Started" section referencing the script
3. **Add a `scripts/` directory** to the repo (new — currently all scripts are inline in Terraform)
4. **NOT modify any Terraform code** — this is purely a workstation preparation tool

### Suggested Change Name

`build-workstation-prerequisites`

---

## 9. Acceptance Criteria

- [ ] `Initialize-BuildWorkstation.ps1` runs on a clean Windows 11 machine and installs all prerequisites
- [ ] Running the script a second time produces no changes (idempotent)
- [ ] After the script completes, `terraform plan -var-file="terraform.tfvars"` succeeds without errors
- [ ] The script works in both Windows PowerShell 5.1 and PowerShell 7+
- [ ] No Azure CLI commands are used in the script output/documentation except for authentication (`az login`, `az account set`)
- [ ] All resource providers are registered and verified before the script exits
