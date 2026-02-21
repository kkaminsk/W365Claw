## MODIFIED Requirements

### Requirement: Version-pinned VS Code installer (M4)
The system SHALL download a specific, pinned version of Visual Studio Code rather than using the `/latest/` redirect URL, ensuring every image build produces the same VS Code version.

#### Problem
`modules/image-builder/main.tf` Phase 2 customizer downloads VS Code from a `/latest/` URL. Each build may install a different VS Code version, breaking reproducibility and making it impossible to attribute issues to a specific editor version.

#### Fix
Pin VS Code to a specific version by adding a variable and constructing the URL:

**File:** `modules/image-builder/variables.tf`
```hcl
variable "vscode_version" {
  description = "VS Code version to install (e.g. 1.96.4)"
  type        = string
  default     = "1.96.4"
}
```

**File:** `modules/image-builder/main.tf` (Phase 2 customizer)
```hcl
# BEFORE
$vscodeUrl = "https://update.code.visualstudio.com/latest/win32-x64/stable"

# AFTER
$vscodeUrl = "https://update.code.visualstudio.com/${var.vscode_version}/win32-x64/stable"
```

#### Scenario: Reproducible VS Code version across builds
- **WHEN** two image builds are executed without changing `var.vscode_version`
- **THEN** both builds SHALL install the same VS Code version

---

### Requirement: Version-pinned GitHub Desktop installer (M5)
The system SHALL download a specific, pinned version of GitHub Desktop rather than using the `/latest/` MSI URL.

#### Problem
`modules/image-builder/main.tf` Phase 2 customizer downloads GitHub Desktop from a `/latest/` URL, causing the same reproducibility issue as VS Code.

#### Fix
Pin GitHub Desktop to a specific version:

**File:** `modules/image-builder/variables.tf`
```hcl
variable "github_desktop_version" {
  description = "GitHub Desktop version to install (e.g. 3.4.12)"
  type        = string
  default     = "3.4.12"
}
```

**File:** `modules/image-builder/main.tf` (Phase 2 customizer)
```hcl
# BEFORE
$ghDesktopUrl = "https://central.github.com/deployments/desktop/desktop/latest/win32"

# AFTER
$ghDesktopUrl = "https://github.com/desktop/desktop/releases/download/release-${var.github_desktop_version}/GitHubDesktopSetup-x64.msi"
```

#### Scenario: Reproducible GitHub Desktop version across builds
- **WHEN** two image builds are executed without changing `var.github_desktop_version`
- **THEN** both builds SHALL install the same GitHub Desktop version
