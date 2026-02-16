## Why

Operators attempting to run `terraform apply` on the W365Claw solution hit avoidable failures — missing Terraform CLI, unregistered resource providers (especially `Microsoft.VirtualMachineImages`), no Azure authentication, or missing Az PowerShell module for post-build verification. There's no documented or automated way to go from a clean Windows machine to "ready to build." This wastes time on every new operator onboarding and after machine reprovisioning.

## What Changes

- **New**: `scripts/Initialize-BuildWorkstation.ps1` — idempotent PowerShell script that checks, installs, and configures all prerequisites
- **New**: `scripts/` directory in the repository (first external script — all existing scripts are inline in Terraform)
- **Modified**: `README.md` — add "Getting Started" section referencing the prerequisite script

## Capabilities

### New Capabilities
- `prerequisite-validation`: Pre-flight check that reports status of all required tools, Azure auth, resource providers, and terraform init state
- `prerequisite-installation`: Interactive installation of missing tools (Terraform, Azure CLI, Git, Az module) via winget with fallbacks
- `provider-registration`: Automated registration and wait-loop verification of required Azure resource providers

### Modified Capabilities
- `documentation`: README updated with getting started workflow

## Impact

- **No Terraform code changes** — this is purely a workstation preparation tool
- **New directory**: `scripts/` added to the repository
- **Dependencies**: Requires `winget` for tool installation (available on Windows 10 1709+ and Windows 11); falls back to direct download for Terraform if winget is unavailable
- **Permissions**: Must run as Administrator for software installation; Azure account needs Contributor + User Access Administrator on the target scope
