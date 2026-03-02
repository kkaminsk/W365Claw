# Fix Trusted Launch on Gallery Image Definition

## Problem

Windows 365 image import fails with:

> Failed adding new image 'W365Claw'. Trusted Launch is not selected on the source Azure Compute Gallery image definition

The current Terraform code in `terraform/modules/gallery/main.tf` uses `features` blocks to declare `SecurityType = TrustedLaunchSupported`. However, the AzureRM provider has a **dedicated attribute** `trusted_launch_supported` on `azurerm_shared_image` that properly sets the security type at the API level. The `features` blocks alone do not satisfy the Windows 365 Trusted Launch validation.

## Root Cause

The `azurerm_shared_image` resource supports four mutually exclusive security attributes (added in AzureRM v3.82+):

- `trusted_launch_supported` — allows both Trusted Launch and standard Gen2 VMs
- `trusted_launch_enabled` — requires Trusted Launch for all VMs
- `confidential_vm_supported`
- `confidential_vm_enabled`

None of these are set in the current code. The `features` blocks are supplemental metadata but don't trigger the provider's security type logic.

## Proposed Fix

1. **Add `trusted_launch_supported = true`** to the `azurerm_shared_image` resource
2. **Keep the existing `features` blocks** — they provide additional W365 compatibility metadata (hibernate, disk controller, accelerated networking, secure boot)
3. **Handle the recreation**: Changing security type forces a new resource. The `prevent_destroy` lifecycle must be temporarily removed, or the existing image definition must be manually destroyed via `terraform state rm` + `terraform import` after recreation

## Impact

- **Breaking change**: The image definition will be destroyed and recreated (Azure does not allow in-place security type changes)
- Any existing image **versions** under the old definition will be lost unless migrated
- Downstream W365 provisioning profiles referencing this image will need re-pointing

## Files Changed

- `terraform/modules/gallery/main.tf` — add `trusted_launch_supported = true`, document recreation plan
- `terraform/modules/gallery/variables.tf` — no changes needed
