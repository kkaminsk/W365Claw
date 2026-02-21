## ADDED Requirements

### Requirement: OpenSpec installed in Phase 3
The system SHALL install OpenSpec (`@fission-ai/openspec`) as a global npm package in Phase 3 (AI Agents), between Claude Code installation and npm audit.

#### Scenario: OpenSpec installed and verified
- **WHEN** Phase 3 executes
- **THEN** `npm install -g @fission-ai/openspec@<version>` SHALL run
- **AND** `Get-Command openspec` SHALL verify the binary is in PATH
- **AND** `openspec --version` output SHALL be logged

#### Scenario: OpenSpec version variable exists
- **GIVEN** root `variables.tf`
- **THEN** a variable `openspec_version` SHALL exist with type `string` and default `"latest"`

#### Scenario: OpenSpec version passed to image-builder module
- **GIVEN** root `main.tf` calls module `image_builder`
- **THEN** `openspec_version` SHALL be passed as an input
- **AND** `modules/image-builder/variables.tf` SHALL declare the variable
