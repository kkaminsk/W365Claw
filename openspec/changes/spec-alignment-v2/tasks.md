## 1. Remove Deprecated Variables

- [x] 1.1 Remove `vscode_version` variable from root `variables.tf`
- [x] 1.2 Remove `github_desktop_version` variable from root `variables.tf`
- [x] 1.3 Remove `vscode_version` and `github_desktop_version` from root `main.tf` module call to `image_builder`
- [x] 1.4 Remove `vscode_version` and `github_desktop_version` from `modules/image-builder/variables.tf`
- [x] 1.5 Remove `vscode_version` and `github_desktop_version` lines from `terraform.tfvars`

## 2. Add OpenSpec Variable

- [x] 2.1 Add `openspec_version` variable to root `variables.tf` (type string, default "latest")
- [x] 2.2 Add `openspec_version` to root `main.tf` module call to `image_builder`
- [x] 2.3 Add `openspec_version` variable to `modules/image-builder/variables.tf`
- [x] 2.4 Add `openspec_version = "latest"` to `terraform.tfvars`

## 3. Update Software Version Defaults

- [x] 3.1 Update `node_version` default to `"v24.13.1"` in root `variables.tf`
- [x] 3.2 Update `python_version` default to `"3.14.3"` in root `variables.tf`
- [x] 3.3 Update `git_version` default to `"2.53.0"` in root `variables.tf`
- [x] 3.4 Update `pwsh_version` default to `"7.4.13"` and description to "PowerShell 7 (LTS) version to install" in root `variables.tf`
- [x] 3.5 Update corresponding values in `terraform.tfvars`

## 4. Update Phase 2 Download URLs

- [x] 4.1 Change VS Code download URL in `modules/image-builder/main.tf` Phase 2 to `https://update.code.visualstudio.com/latest/win32-x64-system/stable` and remove `$VSCodeVersion` variable usage
- [x] 4.2 Change GitHub Desktop download URL in `modules/image-builder/main.tf` Phase 2 to `https://central.github.com/deployments/desktop/desktop/latest/GitHubDesktopSetup-x64.msi` and remove `$GHDesktopVersion` variable usage

## 5. Add OpenSpec to Phase 3

- [x] 5.1 Add OpenSpec installation block in `modules/image-builder/main.tf` Phase 3, after Claude Code and before npm audit: `npm install -g @fission-ai/openspec@${var.openspec_version}`, environment refresh, `Get-Command` verification, version logging

## 6. Update SBOM Manifest

- [x] 6.1 Add `pwshVersion` field to the software manifest hash in Phase 3: `pwshVersion = (pwsh --version 2>&1).ToString()`
- [x] 6.2 Add `openspecVersion` field to the software manifest hash in Phase 3: `openspecVersion = (openspec --version 2>&1).ToString()`

## 7. Validation

- [x] 7.1 Run `terraform fmt -check` on all files
- [x] 7.2 Run `terraform validate` (requires init — may skip if no Azure credentials available)
