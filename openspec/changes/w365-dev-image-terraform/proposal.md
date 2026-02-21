## Why

Platform Engineering needs a reproducible, version-controlled process to build Windows 365 developer images pre-loaded with OpenClaw, Claude Code, and their full dependency chain. Currently there is no automated image build pipeline — images are configured manually, leading to drift, inconsistency, and wasted developer onboarding time. Terraform + Azure Image Builder provides an infrastructure-as-code solution that produces versioned, auditable, Windows 365-compliant images on demand.

## What Changes

- **New**: Azure Compute Gallery with a Windows 365-compliant image definition (Trusted Launch, Hibernate, NVMe, Accelerated Networking, Secure Boot)
- **New**: User-assigned managed identity with least-privilege RBAC (VM Contributor, Network Contributor, Managed Identity Operator, Compute Gallery Image Contributor)
- **New**: Azure VM Image Builder template with inline PowerShell customizers installing Node.js, Python, PowerShell 7, VS Code, Git, GitHub Desktop, OpenClaw, and Claude Code
- **New**: Configuration hydration via Active Setup — OpenClaw config template deployed to each user on first login
- **New**: Enterprise policy for Claude Code (managed-settings.json) and Teams VDI optimisation registry keys
- **New**: SBOM generation and npm audit gate during image build

## Capabilities

### New Capabilities
- `gallery-infrastructure`: Azure Compute Gallery and Windows 365-compliant image definition with all required feature flags
- `identity-rbac`: User-assigned managed identity with least-privilege role assignments scoped to resource group and gallery
- `image-builder-customizers`: AIB template with phased inline PowerShell customizers, Windows Update, restarts, and gallery distribution
- `configuration-hydration`: Active Setup-based first-login config deployment for OpenClaw and Claude Code enterprise settings

### Modified Capabilities
<!-- None — this is a greenfield deployment -->

## Impact

- **Azure resources**: New resource group, Compute Gallery, managed identity, AIB template (all teardown-able after build)
- **Dependencies**: Terraform >= 1.5, AzureRM >= 4.0, azapi >= 2.0; Azure subscription with VirtualMachineImages RP registered
- **Downstream**: Produces gallery image versions consumed by Windows 365 provisioning policies in Intune
- **Cost**: Build VM runs only during image build (~60-90 min); all infra can be destroyed after, leaving only the image version
