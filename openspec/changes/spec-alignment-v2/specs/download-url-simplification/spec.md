## MODIFIED Requirements

### Requirement: VS Code uses latest stable download URL
The Phase 2 customizer SHALL download VS Code using the latest stable system installer URL instead of a version-pinned URL.

#### Scenario: VS Code download URL
- **WHEN** Phase 2 downloads VS Code
- **THEN** the URL SHALL be `https://update.code.visualstudio.com/latest/win32-x64-system/stable`
- **AND** the `vscode_version` variable SHALL be removed from all variable files

### Requirement: GitHub Desktop uses central provisioner URL
The Phase 2 customizer SHALL download GitHub Desktop using the central.github.com provisioner URL instead of a release-pinned URL.

#### Scenario: GitHub Desktop download URL
- **WHEN** Phase 2 downloads GitHub Desktop
- **THEN** the URL SHALL be `https://central.github.com/deployments/desktop/desktop/latest/GitHubDesktopSetup-x64.msi`
- **AND** the `github_desktop_version` variable SHALL be removed from all variable files

## REMOVED Requirements

### Requirement: vscode_version variable removed
The `vscode_version` variable SHALL be removed from root `variables.tf`, `modules/image-builder/variables.tf`, root `main.tf` module call, and `terraform.tfvars`.

### Requirement: github_desktop_version variable removed
The `github_desktop_version` variable SHALL be removed from root `variables.tf`, `modules/image-builder/variables.tf`, root `main.tf` module call, and `terraform.tfvars`.
