## 1. Terraform Variable Wiring

- [x] 1.1 Add `azure_cli_version` variable to `terraform/variables.tf` with default `2.83.0` in the Software Versions section
- [x] 1.2 Add `azure_cli_version` to `terraform/modules/image-builder/variables.tf` as an input variable
- [x] 1.3 Pass `azure_cli_version` from root `terraform/main.tf` to the `image_builder` module block
- [x] 1.4 Add `azure_cli_version = "2.83.0"` to `terraform/terraform.tfvars`

## 2. Phase 2 Customizer — Azure CLI Installation

- [x] 2.1 Add Azure CLI MSI download and install block to the `InstallDevTools` customizer in `terraform/modules/image-builder/main.tf`, after GitHub Desktop and before the cleanup step
- [x] 2.2 Use `Get-InstallerWithRetry` for download from `azcliprod.blob.core.windows.net/msi/azure-cli-<version>-x64.msi`
- [x] 2.3 Install via `msiexec.exe /i ... /qn /norestart ALLUSERS=1` with exit-code check
- [x] 2.4 Call `Update-SessionEnvironment` after install and verify with `az --version | Select-Object -First 1`
- [x] 2.5 Add `$AzCliInstaller` to the Phase 2 `Remove-Item` cleanup line

## 3. SBOM and Validation

- [x] 3.1 Add `azCliVersion` field to the software manifest hash table in the Phase 3 `InstallAIAgents` customizer
- [x] 3.2 Add `az --version` checklist item to the Validation Checklist section in `TerraformApplicationSpecification.md`

## 4. Spec Documentation

- [x] 4.1 Update `TerraformApplicationSpecification.md` overview to list Azure CLI among installed tools
- [x] 4.2 Update the example `terraform.tfvars` section in the spec to include `azure_cli_version`
