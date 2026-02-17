## 1. Pin OpenSpec Version

- [x] 1.1 Change `openspec_version` default in `terraform/variables.tf` from `latest` to a specific version
- [x] 1.2 Update `terraform/terraform.tfvars` to use pinned OpenSpec version

## 2. Add SHA256 Checksum Variables

- [x] 2.1 Add `node_sha256`, `python_sha256`, `pwsh_sha256`, `git_sha256`, `azure_cli_sha256` variables to `terraform/variables.tf`
- [x] 2.2 Add corresponding values to `terraform/terraform.tfvars`
- [x] 2.3 Pass SHA256 variables through root `terraform/main.tf` to image-builder module
- [x] 2.4 Add SHA256 input variables to `terraform/modules/image-builder/variables.tf`

## 3. Add Integrity Verification to Image Builder

- [x] 3.1 Add `Test-InstallerHash` helper function to Phase 1 (InstallCoreRuntimes)
- [x] 3.2 Add hash verification after Node.js download
- [x] 3.3 Add hash verification after Python download
- [x] 3.4 Add hash verification after PowerShell 7 download
- [x] 3.5 Add `Test-InstallerHash` helper function to Phase 2 (InstallDevTools)
- [x] 3.6 Add hash verification after Git download
- [x] 3.7 Add hash verification after Azure CLI download
