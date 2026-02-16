# W365Claw

Automated Windows 365 developer image build using Terraform and Azure VM Image Builder. Produces gallery images pre-loaded with OpenClaw, Claude Code, and a full developer toolchain.

## What's Included

The image installs and configures:

- **Runtimes:** Node.js, Python, PowerShell 7
- **Developer Tools:** VS Code, Git, GitHub Desktop
- **AI Agents:** OpenClaw, Claude Code
- **Enterprise Config:** Claude Code managed settings, OpenClaw config hydration via Active Setup, Teams VDI optimisation
- **Security:** SBOM generation, npm audit gate (fails on high/critical vulnerabilities)

## Architecture

```
terraform/
├── main.tf                          # Root module — orchestrates gallery, identity, image-builder
├── variables.tf                     # All configurable inputs with defaults
├── outputs.tf                       # Gallery IDs, build log info, next steps runbook
├── versions.tf                      # Provider requirements (azurerm, azapi, time)
├── terraform.tfvars                 # Environment-specific values (git-ignored)
└── modules/
    ├── gallery/                     # Azure Compute Gallery + W365-compliant image definition
    ├── identity/                    # User-assigned managed identity + least-privilege RBAC
    └── image-builder/               # AIB template with phased inline PowerShell customizers

openspec/
└── changes/
    ├── w365-dev-image-terraform/    # Original build proposal, design, specs, tasks
    └── terraform-audit-remediation/ # Audit fix proposals (H1, H2, M1-M5, L1, L4)
```

## Prerequisites

- Terraform >= 1.5
- Azure subscription with these resource providers registered:
  - `Microsoft.Compute`
  - `Microsoft.VirtualMachineImages`
  - `Microsoft.Network`
  - `Microsoft.ManagedIdentity`
- PowerShell with the `Az` module (for verification and cleanup commands)

## Quick Start

```powershell
Set-Location terraform

# Initialise
terraform init

# Plan
terraform plan -var-file="terraform.tfvars" -out tfplan

# Apply (deploys infra + triggers image build)
terraform apply tfplan

# After build completes and image is verified, tear down build resources
terraform destroy
```

## Version Bump

```powershell
terraform apply `
  -var='image_version=1.1.0' `
  -var='exclude_from_latest=true'

# After pilot validation, promote
terraform apply `
  -var='image_version=1.1.0' `
  -var='exclude_from_latest=false'
```

## Verify Image

```powershell
Get-AzGalleryImageVersion `
  -ResourceGroupName "rg-w365-images" `
  -GalleryName "acgW365Dev" `
  -GalleryImageDefinitionName "W365-W11-25H2-ENU" |
  Format-Table Name, ProvisioningState, PublishingProfile
```

## Windows 365 Compliance

The image definition includes all required feature flags:

| Feature | Value |
|---------|-------|
| SecurityType | TrustedLaunchSupported |
| IsHibernateSupported | True |
| DiskControllerTypes | SCSI, NVMe |
| IsAcceleratedNetworkSupported | True |
| IsSecureBootSupported | True |

## Documentation

- **[TerraformApplicationSpecification.md](TerraformApplicationSpecification.md)** — Full specification with all HCL, runbook, and security considerations
- **[TerraformAudit.md](TerraformAudit.md)** — Engineering audit with findings and remediation status

## Cost

All infrastructure (identity, AIB template, build VM) can be destroyed after the build. Only the gallery image version persists — and that's what Windows 365 provisioning policies consume.

**Workflow:** `terraform apply` → wait for build (~60-90 min) → verify → `terraform destroy`
