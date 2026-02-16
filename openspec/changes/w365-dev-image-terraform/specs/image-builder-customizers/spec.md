## ADDED Requirements

### Requirement: AIB template via azapi provider
The system SHALL define the Azure Image Builder template using the `azapi` provider (`Microsoft.VirtualMachineImages/imageTemplates`) for full ARM API coverage of customizers, distributors, and VM profile.

#### Scenario: Template created with azapi
- **WHEN** `terraform apply` is executed
- **THEN** an `azapi_resource` of type `Microsoft.VirtualMachineImages/imageTemplates@2024-02-01` SHALL be created with the user-assigned managed identity

### Requirement: Phased inline PowerShell customizers
The system SHALL install software in four ordered phases via inline PowerShell customizers: (1) Core Runtimes — Node.js, Python, PowerShell 7; (2) Developer Tools — VS Code, Git, GitHub Desktop; (3) AI Agents — OpenClaw, Claude Code with npm audit and SBOM; (4) Configuration & Policy — Claude Code managed settings, OpenClaw template, Active Setup, Teams VDI, cleanup.

#### Scenario: Phase 1 installs runtimes
- **WHEN** the image build executes Phase 1
- **THEN** Node.js (pinned version >= 22), Python (pinned version), and PowerShell 7 SHALL be installed system-wide with PATH updated

#### Scenario: Phase 3 runs npm audit
- **WHEN** OpenClaw and Claude Code are installed
- **THEN** `npm audit --global --audit-level=high` SHALL be executed and the build SHALL fail if high or critical vulnerabilities are found

#### Scenario: SBOM generated
- **WHEN** Phase 3 completes
- **THEN** `C:\ProgramData\ImageBuild\sbom-npm-global.json` and `sbom-software-manifest.json` SHALL exist

### Requirement: Pinned source image version
The system SHALL require a pinned source marketplace image version (not "latest") for build reproducibility.

#### Scenario: Source version "latest" rejected
- **WHEN** `source_image_version` is set to "latest"
- **THEN** Terraform SHALL reject the input with a validation error

### Requirement: Windows Update and restart phases
The system SHALL apply Windows Updates (excluding Preview updates) and perform restarts between phases to ensure a fully patched image.

#### Scenario: Windows Update applied
- **WHEN** the customizer sequence executes
- **THEN** a WindowsUpdate customizer SHALL run with `IsInstalled=0` search criteria, excluding Preview updates, with a limit of 40 updates

### Requirement: Gallery distribution with version control
The system SHALL distribute the built image to the Azure Compute Gallery with configurable version, exclude_from_latest flag, replica count, and 90-day end-of-life.

#### Scenario: Image distributed to gallery
- **WHEN** the image build completes successfully
- **THEN** an image version SHALL be created in the gallery with the specified version number, replication region, and Standard_LRS storage

### Requirement: Build trigger
The system SHALL automatically trigger the image build after the template is created using `azapi_resource_action` with a "run" action.

#### Scenario: Build triggered on apply
- **WHEN** `terraform apply` completes template creation
- **THEN** the build SHALL be triggered automatically with a timeout of `build_timeout_minutes + 30` minutes
