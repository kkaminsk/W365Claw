## ADDED Requirements

### Requirement: Interactive installation with confirmation
The script SHALL prompt the operator before installing each missing tool unless the `-Force` parameter is passed.

#### Scenario: Prompt before install
- **WHEN** Terraform is missing and `-Force` is not set
- **THEN** the script SHALL ask "Install Terraform via winget? [Y/n]" and proceed only on confirmation

#### Scenario: Force mode skips prompts
- **WHEN** `-Force` is passed
- **THEN** all installations SHALL proceed without prompting

### Requirement: Terraform installation
The script SHALL install Terraform via `winget install Hashicorp.Terraform` with a fallback to direct ZIP download if winget is unavailable.

#### Scenario: winget available
- **WHEN** Terraform is missing and winget is available
- **THEN** `winget install Hashicorp.Terraform --silent` SHALL be executed

#### Scenario: winget unavailable
- **WHEN** Terraform is missing and winget is not available
- **THEN** the latest Terraform ZIP SHALL be downloaded from releases.hashicorp.com, extracted to `C:\Tools\Terraform`, and added to the system PATH

#### Scenario: PATH refresh after install
- **WHEN** any tool is installed
- **THEN** the session PATH SHALL be refreshed to include the new binary

### Requirement: Azure CLI installation
The script SHALL install Azure CLI via `winget install Microsoft.AzureCLI --silent` when missing.

### Requirement: Git installation
The script SHALL install Git via `winget install Git.Git --silent` when missing.

### Requirement: Az PowerShell module installation
The script SHALL install the Az module via `Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force` when missing or below minimum version.

#### Scenario: PSGallery trust
- **WHEN** PSGallery is untrusted
- **THEN** the script SHALL set it to Trusted before installing

### Requirement: Azure login
The script SHALL launch `az login` when the operator is not authenticated, then prompt for subscription selection if multiple subscriptions exist.

#### Scenario: Single subscription
- **WHEN** the operator logs in and has one subscription
- **THEN** it SHALL be selected automatically

#### Scenario: Multiple subscriptions
- **WHEN** the operator has multiple subscriptions
- **THEN** the script SHALL list them and prompt for selection via `az account set --subscription`

### Requirement: Idempotency
The script SHALL not reinstall tools that are already present at or above the minimum version. It SHALL not re-register already-registered resource providers. Running the script twice SHALL produce no changes on the second run.

### Requirement: No downgrades
The script SHALL never downgrade existing software. If a tool is installed above the minimum version, it SHALL be reported as passing.

### Requirement: Exit codes
- **Exit 0**: All prerequisites met after installation
- **Exit 1**: One or more prerequisites could not be installed or configured
