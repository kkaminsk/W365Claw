## MODIFIED Requirements

### Requirement: Software version defaults match application specification
The root `variables.tf` default values SHALL match the versions specified in `TerraformApplicationSpecification.md`.

#### Scenario: Node.js version default updated
- **GIVEN** `variables.tf` defines `node_version`
- **THEN** the default SHALL be `"v24.13.1"`

#### Scenario: Python version default updated
- **GIVEN** `variables.tf` defines `python_version`
- **THEN** the default SHALL be `"3.14.3"`

#### Scenario: Git version default updated
- **GIVEN** `variables.tf` defines `git_version`
- **THEN** the default SHALL be `"2.53.0"`

#### Scenario: PowerShell version default updated
- **GIVEN** `variables.tf` defines `pwsh_version`
- **THEN** the default SHALL be `"7.4.13"` and the description SHALL read "PowerShell 7 (LTS) version to install"

#### Scenario: terraform.tfvars updated
- **GIVEN** `terraform.tfvars` exists
- **THEN** pinned software versions SHALL match the new defaults

### Requirement: SBOM software manifest includes all installed software
The SBOM manifest generated in Phase 3 SHALL include version entries for all installed software including PowerShell 7 and OpenSpec.

#### Scenario: Manifest includes pwsh and openspec
- **WHEN** Phase 3 generates `sbom-software-manifest.json`
- **THEN** the JSON SHALL include `pwshVersion` and `openspecVersion` fields
