# W365Claw

Automated Windows 365 developer image build using Terraform and Azure VM Image Builder. Produces Azure Compute Gallery images pre-loaded with a full developer toolchain, ready for Windows 365 Cloud PC provisioning.

AI agents (OpenClaw, Claude Code, Codex CLI) are delivered **post-provisioning** via Intune in user context — not baked into the image. The image handles runtimes, developer tools, enterprise policy, and configuration templates.

## Companion Book

This repository is the companion code for **[Deploying OpenClaw with Windows 365: A Practitioner's Guide to Custom Image Engineering and Deployment](https://github.com/kkaminsk/W365ClawBook)** by Kevin Kaminski, Microsoft MVP for Windows 365. The book covers the full end-to-end architecture, security model, build pipeline, and operational runbooks. Download the [PDF](https://raw.githubusercontent.com/kkaminsk/W365ClawBook/main/W365Claw.pdf).

## What's in the Image

| Category | Components |
|---|---|
| **Runtimes** | Node.js 24.x, Python 3.14.x, PowerShell 7.4.x |
| **Developer Tools** | VS Code (System install), Git 2.53.x, GitHub Desktop, Azure CLI 2.83.x |
| **Enterprise Config** | Claude Code managed-settings.json, OpenClaw config hydration via Active Setup, VS Code context menu integration |
| **Security** | SBOM generation, SHA-256 installer checksums, pinned software versions |

## What's Delivered Post-Provisioning (via Intune)

| Component | Mechanism |
|---|---|
| **OpenClaw** | Intune Win32 app (per-user, `npm install -g openclaw`) |
| **Claude Code** | Intune Win32 app (per-user, `npm install -g @anthropic-ai/claude-code`) |
| **OpenAI Codex CLI** | Intune Win32 app (per-user) |
| **OpenSpec** | Intune Win32 app (per-user) |
| **API Keys** | Intune Settings Catalog (environment variables) |
| **VS Code Extensions** | Intune script (GitHub Copilot, etc.) |
| **Agent Skills / MCP Config** | Active Setup hydration from ProgramData templates |

## Architecture

```
W365Claw/
├── terraform/
│   ├── main.tf                          # Root module — orchestrates gallery, identity, image-builder
│   ├── variables.tf                     # All configurable inputs with defaults
│   ├── outputs.tf                       # Gallery IDs, build log info, next steps runbook
│   ├── versions.tf                      # Provider requirements (azurerm, azapi, time)
│   ├── terraform.tfvars                 # Environment-specific values (git-ignored)
│   └── modules/
│       ├── gallery/                     # Azure Compute Gallery + W365-compliant image definition
│       ├── identity/                    # User-assigned managed identity + least-privilege RBAC
│       └── image-builder/               # AIB template with phased inline PowerShell customizers
├── scripts/
│   ├── Initialize-BuildWorkstation.ps1  # Prerequisite checker and installer
│   ├── Initialize-TerraformVars.ps1     # Generates terraform.tfvars from tenant context
│   └── Teardown-BuildResources.ps1      # Targeted teardown (preserves gallery resources)
├── openspec/
│   └── changes/                         # OpenSpec proposals: design, specs, and task tracking
├── CLAUDE.md                            # Claude Code project context
├── ConfigurationSpecification.md        # Full configuration specification
├── TerraformApplicationSpecification.md # Terraform HCL specification and runbook
├── TerraformAudit.md                    # Engineering audit findings and remediation
└── supply-chain-integrity.md            # SBOM and supply chain documentation
```

## Prerequisites

- Terraform >= 1.5
- Azure CLI >= 2.60
- Git >= 2.40
- Az PowerShell module >= 12.0 (for post-build verification)
- Azure subscription with these resource providers registered:
  - `Microsoft.Compute`
  - `Microsoft.VirtualMachineImages`
  - `Microsoft.Network`
  - `Microsoft.ManagedIdentity`

## Getting Started

Run the prerequisite script to check and install everything automatically:

```powershell
# Interactive — prompts before each installation
.\scripts\Initialize-BuildWorkstation.ps1

# Non-interactive — installs everything without prompting
.\scripts\Initialize-BuildWorkstation.ps1 -Force
```

Generate `terraform.tfvars` from your tenant context:

```powershell
.\scripts\Initialize-TerraformVars.ps1
```

The scripts check all prerequisites, install what's missing (via winget), log into Azure, register resource providers, and run `terraform init`. See [ConfigurationSpecification.md](ConfigurationSpecification.md) for full details.

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
# NOTE: Do NOT run `terraform destroy` — gallery resources have prevent_destroy = true.
# Use the targeted teardown script instead:
..\scripts\Teardown-BuildResources.ps1
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

The image definition includes all required feature flags for Windows 365 ACG import:

| Feature | Value |
|---------|-------|
| Trusted Launch | Enabled |
| Hibernation | Enabled |
| NVMe Disk Controller | Enabled |
| Accelerated Networking | Enabled |
| Hyper-V Generation | V2 |
| Architecture | x64 |
| OS State | Generalized |

## Documentation

- **[ConfigurationSpecification.md](ConfigurationSpecification.md)** — Full configuration specification with build workstation setup
- **[TerraformApplicationSpecification.md](TerraformApplicationSpecification.md)** — Complete Terraform HCL specification, runbook, and security considerations
- **[TerraformAudit.md](TerraformAudit.md)** — Engineering audit findings and remediation status
- **[supply-chain-integrity.md](supply-chain-integrity.md)** — SBOM generation and supply chain documentation
- **[W365ClawBook](https://github.com/kkaminsk/W365ClawBook)** — Companion book with full architecture, security model, and operational guidance

## Cost

Build-time infrastructure (identity, AIB template, build VM) can be removed after the build. The gallery and image versions are protected by `prevent_destroy` and persist for Windows 365 provisioning.

**Workflow:** `terraform apply` → wait for build (~75–120 min) → verify → `.\scripts\Teardown-BuildResources.ps1`

## License

See [LICENSE](LICENSE).
