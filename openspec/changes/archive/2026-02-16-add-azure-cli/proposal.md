## Why

Developers provisioned onto Windows 365 Cloud PCs from the W365Claw image currently have no way to run `az` commands without manually installing Azure CLI. Many day-to-day Azure workflows — querying resources, tailing logs, ad-hoc ARM operations — are faster with `az` than with the Az PowerShell module, and several third-party tools and extensions assume `az` is present. Shipping Azure CLI pre-installed eliminates a manual post-provisioning step and keeps the image self-contained.

## What Changes

- **New variable**: `azure_cli_version` (default `2.83.0`) added to `variables.tf` for version-pinned installation
- **New install block**: Azure CLI MSI installation added to Phase 2 (Developer Tools) in the image-builder customizers, using the same retry/verify pattern as existing tools
- **Updated SBOM**: Software manifest in Phase 3 now records the installed Azure CLI version
- **Updated root module**: `main.tf` passes `azure_cli_version` through to the image-builder module
- **Updated tfvars example**: `terraform.tfvars` includes `azure_cli_version`
- **Updated validation checklist**: `az --version` added to post-build verification steps
- **Updated overview**: Azure CLI listed among installed tools

## Capabilities

### New Capabilities
- `azure-cli-installation`: Version-pinned MSI installation of Azure CLI in the AIB image build, with download retry, exit-code verification, and PATH refresh

### Modified Capabilities
<!-- No existing spec-level capabilities are changing — this is purely additive -->

## Impact

- **Terraform code**: New variable in `variables.tf`, new pass-through in root `main.tf`, new inline PowerShell block in `modules/image-builder/main.tf`
- **Image size**: Azure CLI MSI adds ~500 MB to the built image (installed footprint)
- **Build time**: Adds ~2-3 minutes for download + MSI install; well within the 120-minute timeout
- **Dependencies**: None — Azure CLI MSI is a standalone installer with no prerequisites beyond Windows
- **Convention note**: The project convention "PowerShell everywhere, no Azure CLI" applies to project scripting and documentation. Azure CLI is being shipped as an end-user tool, not used in build automation
