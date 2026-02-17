## Why

The gallery and image definition have `prevent_destroy = true` lifecycle rules, but README.md and outputs.tf instruct users to run `terraform destroy`. This is contradictory — `terraform destroy` will fail on protected resources, leaving operators confused with partially managed state.

## What Changes

- **README.md**: Replace `terraform destroy` guidance with targeted resource removal instructions using `scripts/Teardown-BuildResources.ps1`
- **outputs.tf**: Update the "next steps" output to document targeted teardown instead of blanket destroy
- **New script**: `scripts/Teardown-BuildResources.ps1` that removes only the AIB template and build-time resources while preserving the gallery

## Capabilities

### New Capabilities
- `targeted-teardown`: PowerShell script to remove only AIB template resources, preserving the gallery and image versions

### Modified Capabilities
- `teardown-documentation`: README and outputs now correctly describe targeted resource removal

## Impact

- **Documentation**: README.md and outputs.tf updated
- **New file**: `scripts/Teardown-BuildResources.ps1`
- **No Terraform code changes**: Gallery lifecycle rules remain as-is
