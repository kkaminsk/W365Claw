# Tasks

- [ ] Add `trusted_launch_supported = true` to `azurerm_shared_image.this` in `terraform/modules/gallery/main.tf`
- [ ] Temporarily remove `prevent_destroy` lifecycle or use `terraform state rm` to handle forced recreation
- [ ] Run `terraform plan` to confirm the image definition will be recreated with correct security type
- [ ] Apply the change and verify via `az sig image-definition show` that `SecurityType: TrustedLaunchSupported` appears
- [ ] Restore `prevent_destroy` lifecycle after successful apply
- [ ] Re-create any image versions under the new definition (re-run image build pipeline)
- [ ] Test W365 image import with the updated gallery image definition
