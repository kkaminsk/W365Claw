# Terraform Application Specification: W365Claw Developer Image

---

## Overview

This specification defines the complete Terraform configuration for building Windows 365-compatible developer images using Azure VM Image Builder (AIB). The infrastructure uses a single resource group with modular Terraform to produce versioned, generalized images in an Azure Compute Gallery.

The solution is manually invoked via `terraform apply` — there is no CI/CD pipeline.

### What This Deploys

1. **Azure Compute Gallery** (`acgW365Dev`) with a Windows 365-compliant image definition (`W365-W11-25H2-ENU`)
2. **User-assigned managed identity** (`id-aib-w365-dev`) with least-privilege RBAC for AIB
3. **Azure VM Image Builder template** with phased inline PowerShell customizers that install runtimes, developer tools, enterprise configuration, and security hardening

### What Is Out of Scope

- **AI agent installation** (OpenClaw, Claude Code, Codex CLI, OpenSpec) — delivered post-provisioning via Intune Win32 apps in user context
- **API key management** — each user manages their own ANTHROPIC_API_KEY after login
- **VS Code extensions** — installed via Intune scripts post-provisioning
- **Intune / provisioning policy configuration** — managed separately by the administrator
- **CI/CD pipelines** — the solution is invoked manually

---

## Directory Structure

```
terraform/
├── main.tf                          # Root module — orchestrates three child modules
├── variables.tf                     # All configurable inputs with defaults and validations
├── outputs.tf                       # Gallery IDs, build log info, next-steps runbook
├── versions.tf                      # Provider requirements and backend configuration
├── terraform.tfvars                 # Environment-specific values (git-ignored)
├── .terraform.lock.hcl              # Provider lock file
└── modules/
    ├── gallery/                     # Azure Compute Gallery + image definition
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── identity/                    # User-assigned managed identity + RBAC assignments
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── image-builder/               # AIB template with inline PowerShell customizers
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── versions.tf
```

---

## Providers

| Provider | Source | Version Constraint |
|----------|--------|--------------------|
| `azurerm` | `hashicorp/azurerm` | `~> 4.0` |
| `azapi` | `azure/azapi` | `~> 2.0` |
| `time` | `hashicorp/time` | `~> 0.11` |

**Terraform version:** `>= 1.5.0`

**Backend:** Local (state stored on the build workstation — no remote backend).

---

## Module Architecture

### Root Module (`terraform/main.tf`)

Orchestrates three child modules with explicit dependency chaining:

```
azurerm_resource_group.images
    ├── module.gallery       → Compute Gallery + image definition
    ├── module.identity      → Managed identity + RBAC (depends on gallery)
    └── module.image_builder → AIB template (depends on identity + gallery)
```

### Module: `gallery`

Creates the Azure Compute Gallery and image definition with Windows 365-required feature flags:

| Feature | Value | Purpose |
|---------|-------|---------|
| `trusted_launch_enabled` | `true` | W365 ACG import requirement |
| `hibernation_enabled` | `true` | W365 ACG import requirement |
| `disk_controller_type_nvme_enabled` | `true` | W365 ACG import requirement |
| `accelerated_network_support_enabled` | `true` | W365 ACG import requirement |
| `hyper_v_generation` | `V2` | W365 ACG import requirement |
| `os_type` | `Windows` | — |
| `architecture` | `x64` | — |

Both the gallery and image definition have `lifecycle { prevent_destroy = true }` to protect production images.

### Module: `identity`

Creates a user-assigned managed identity with least-privilege RBAC:

| Role | Scope | Purpose |
|------|-------|---------|
| Virtual Machine Contributor | Resource Group | AIB creates/manages the build VM |
| Network Contributor | Resource Group | AIB creates transient networking |
| Managed Identity Operator | Resource Group | AIB assigns the identity to the build VM |
| Compute Gallery Artifacts Publisher | Gallery | AIB writes image versions |

### Module: `image-builder`

Creates the AIB template using the `azapi_resource` provider (type: `Microsoft.VirtualMachineImages/imageTemplates`). Key characteristics:

- **Inline PowerShell customizers** — no external storage account required
- **Phased installation** with environment refresh between phases
- **SHA-256 checksum verification** for all downloaded installers (when checksums are provided)
- **Retry logic** on downloads (3 attempts with 10-second backoff)
- **Build timeout:** 120 minutes (configurable)
- **Build VM:** `Standard_D4s_v5` (configurable)
- **OS disk:** 128 GB (configurable)
- **Image end-of-life:** 90 days from build time (via `time_static` to avoid perpetual diffs)

---

## Variables

### Infrastructure

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `subscription_id` | `string` | — (required) | Azure subscription ID |
| `location` | `string` | `eastus2` | Azure region |
| `resource_group_name` | `string` | `rg-w365-images` | Resource group name |
| `gallery_name` | `string` | `acgW365Dev` | Gallery name (alphanumeric only) |
| `image_definition_name` | `string` | `W365-W11-25H2-ENU` | Image definition name |
| `image_publisher` | `string` | `BigHatGroupInc` | Publisher identifier |
| `image_offer` | `string` | `W365-W11-25H2-ENU` | Offer identifier |
| `image_sku` | `string` | `W11-25H2-ENT-Dev` | SKU identifier |

### Image Versioning

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `image_version` | `string` | `1.0.0` | Semantic version (Major.Minor.Patch) |
| `exclude_from_latest` | `bool` | `true` | Set `false` to promote to production |
| `replica_count` | `number` | `1` | Replicas per region |

### Build VM

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `build_vm_size` | `string` | `Standard_D4s_v5` | Build VM SKU |
| `build_timeout_minutes` | `number` | `120` | Max build duration |
| `os_disk_size_gb` | `number` | `128` | OS disk size |

### Source Image

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `source_image_publisher` | `string` | `MicrosoftWindowsDesktop` | Marketplace publisher |
| `source_image_offer` | `string` | `windows-11` | Marketplace offer |
| `source_image_sku` | `string` | `win11-25h2-ent` | Marketplace SKU |
| `source_image_version` | `string` | `26200.7840.260206` | Pinned version (never `latest`) |

### Software Versions

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `node_version` | `string` | `v24.13.1` | Node.js (must be >= v22) |
| `python_version` | `string` | `3.14.3` | Python |
| `git_version` | `string` | `2.53.0` | Git for Windows |
| `pwsh_version` | `string` | `7.4.13` | PowerShell 7 LTS |
| `azure_cli_version` | `string` | `2.83.0` | Azure CLI |

### SHA-256 Checksums

Optional checksums for installer integrity verification. When provided, the build fails if the downloaded file doesn't match.

| Variable | Default |
|----------|---------|
| `node_sha256` | `""` (skip) |
| `python_sha256` | `""` (skip) |
| `pwsh_sha256` | `""` (skip) |
| `git_sha256` | `""` (skip) |
| `azure_cli_sha256` | `""` (skip) |

### OpenClaw Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `openclaw_default_model` | `string` | `anthropic/claude-opus-4-6` | Default LLM model for config template |
| `openclaw_gateway_port` | `number` | `18789` | Gateway port |
| `skills_repo_url` | `string` | `""` | Git URL for agent skills (empty to skip) |

### Tags

| Variable | Type | Default |
|----------|------|---------|
| `tags` | `map(string)` | `{ workload = "Windows365", purpose = "DeveloperImages", managed_by = "PlatformEngineering", iac = "Terraform" }` |

---

## Outputs

| Output | Description |
|--------|-------------|
| `gallery_id` | Azure Compute Gallery resource ID |
| `image_definition_id` | Image definition resource ID |
| `managed_identity_id` | AIB managed identity resource ID |
| `managed_identity_principal_id` | AIB managed identity principal ID |
| `image_template_name` | AIB image template name |
| `build_log_info` | Where to find AIB build logs |
| `next_steps` | Post-build runbook (verify, teardown, import to W365, promote) |

---

## Build Workflow

### Prerequisites

Run the build workstation setup script:

```powershell
.\scripts\Initialize-BuildWorkstation.ps1 -Force
.\scripts\Initialize-TerraformVars.ps1
```

This installs Terraform, Azure CLI, Git, and Az PowerShell module; logs into Azure; registers resource providers; and generates `terraform.tfvars`.

### Build

```powershell
cd terraform
terraform init
terraform plan -var-file="terraform.tfvars" -out tfplan
terraform apply tfplan
```

The apply creates all infrastructure and submits the AIB build. The build runs asynchronously (75–120 minutes).

### Verify

```powershell
Get-AzGalleryImageVersion `
  -ResourceGroupName "rg-w365-images" `
  -GalleryName "acgW365Dev" `
  -GalleryImageDefinitionName "W365-W11-25H2-ENU" |
  Format-Table Name, ProvisioningState, PublishingProfile
```

### Teardown (Cost Optimization)

After the build completes and the image is verified, remove build infrastructure:

```powershell
..\scripts\Teardown-BuildResources.ps1
```

> **Do NOT run `terraform destroy`** — the gallery and image definition have `prevent_destroy = true` and destroy will fail.

### Promote

Once validated in pilot:

```powershell
terraform apply -var='exclude_from_latest=false'
```

### Version Bump

```powershell
terraform apply `
  -var='image_version=1.1.0' `
  -var='exclude_from_latest=true'
```

---

## Security Considerations

- **Least-privilege RBAC** — the AIB identity has only the four roles it needs, scoped to the resource group and gallery
- **Pinned source image** — `source_image_version` validation rejects `latest`
- **Supply chain integrity** — SHA-256 checksums for all installers; SBOM generation during build
- **No secrets in state** — API keys are user-managed post-provisioning, not embedded in the image
- **Local state** — Terraform state stays on the build workstation (no remote backend exposure)
- **Inline scripts** — no storage account or external script dependencies
- **Gallery protection** — `prevent_destroy` lifecycle on gallery and image definition

---

## Cost Optimization

- **Ephemeral infrastructure** — tear down AIB template, identity, and RBAC after each build
- **Single replica** — one replica per region by default
- **No persistent storage** — all scripts inline, no storage account
- **Build timeout** — 120-minute cap prevents runaway costs
- **Gallery persists** — only the gallery and image versions remain (minimal ongoing cost)

**Recommended workflow:** `terraform apply` → wait for build → verify image → `Teardown-BuildResources.ps1`

---

## Helper Scripts

| Script | Purpose |
|--------|---------|
| `scripts/Initialize-BuildWorkstation.ps1` | Check and install all prerequisites (Terraform, Azure CLI, Git, Az module) |
| `scripts/Initialize-TerraformVars.ps1` | Generate `terraform.tfvars` from current Azure tenant context |
| `scripts/Teardown-BuildResources.ps1` | Targeted teardown of build resources (preserves gallery) |

---

## Related Documents

- [README.md](README.md) — Project overview and quick start
- [ConfigurationSpecification.md](ConfigurationSpecification.md) — Full configuration specification
- [TerraformAudit.md](TerraformAudit.md) — Engineering audit findings and remediation
- [supply-chain-integrity.md](supply-chain-integrity.md) — SBOM and supply chain documentation
- [W365ClawBook](https://github.com/kkaminsk/W365ClawBook) — Companion book with full architecture and operational guidance
