## ADDED Requirements

### Requirement: Azure CLI version variable
The system SHALL define a Terraform variable `azure_cli_version` of type `string` that pins the Azure CLI version to install. The default value SHALL be `2.83.0`.

#### Scenario: Variable declared in variables.tf
- **WHEN** the Terraform configuration is loaded
- **THEN** `var.azure_cli_version` SHALL be available with default `2.83.0`

#### Scenario: Variable passed through root module
- **WHEN** `terraform plan` is executed
- **THEN** `azure_cli_version` SHALL be passed from root `main.tf` to the `image-builder` module

#### Scenario: Variable overridden in tfvars
- **WHEN** an operator sets `azure_cli_version = "2.84.0"` in `terraform.tfvars`
- **THEN** the build SHALL install Azure CLI version `2.84.0`

### Requirement: Azure CLI MSI installation in Phase 2
The system SHALL install Azure CLI in the Phase 2 (Developer Tools) customizer using the MSI installer downloaded from `https://azcliprod.blob.core.windows.net/msi/azure-cli-<version>-x64.msi`. The installation SHALL run silently with `ALLUSERS=1`.

#### Scenario: Successful installation
- **WHEN** the Phase 2 customizer executes
- **THEN** Azure CLI SHALL be downloaded using `Get-InstallerWithRetry`
- **AND** installed via `msiexec.exe /i ... /qn /norestart ALLUSERS=1`
- **AND** the session PATH SHALL be refreshed via `Update-SessionEnvironment`
- **AND** the build log SHALL include a `[VERIFY]` line showing the installed Azure CLI version

#### Scenario: Download failure with retry
- **WHEN** the initial download of the Azure CLI MSI fails
- **THEN** the system SHALL retry up to 3 times with 10-second backoff (via `Get-InstallerWithRetry`)

#### Scenario: Installation failure
- **WHEN** `msiexec.exe` returns a non-zero exit code
- **THEN** the build SHALL fail with error message `"Azure CLI installation failed ($exitCode)"`

#### Scenario: Installer cleanup
- **WHEN** Azure CLI installation completes
- **THEN** the MSI installer file SHALL be removed from `$env:TEMP` in the Phase 2 cleanup step

### Requirement: Azure CLI version in SBOM
The system SHALL include the installed Azure CLI version in the software manifest SBOM generated during Phase 3.

#### Scenario: SBOM includes Azure CLI
- **WHEN** Phase 3 generates `C:\ProgramData\ImageBuild\sbom-software-manifest.json`
- **THEN** the JSON SHALL include an `azCliVersion` field containing the output of `az --version` (first line)

### Requirement: Azure CLI in validation checklist
The post-build validation checklist SHALL include verification that `az --version` returns the expected Azure CLI version.

#### Scenario: Validation checklist entry
- **WHEN** an operator reviews the validation checklist in the specification
- **THEN** there SHALL be a checklist item: `az --version returns expected Azure CLI version`
