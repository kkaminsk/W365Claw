## ADDED Requirements

### Requirement: OS and privilege validation
The script SHALL verify the host is Windows 10/11 x64 and running as Administrator before proceeding.

#### Scenario: Non-admin execution
- **WHEN** the script is run without Administrator privileges
- **THEN** it SHALL print an error and exit with code 1

### Requirement: Tool version detection
The script SHALL detect the installed version of Terraform, Azure CLI, Git, and the Az PowerShell module, comparing against minimum required versions.

#### Scenario: Terraform installed and sufficient
- **WHEN** `terraform version` returns >= 1.5.0
- **THEN** the check SHALL report ✅ with the installed version

#### Scenario: Terraform missing
- **WHEN** `terraform` is not found in PATH
- **THEN** the check SHALL report ❌ MISSING

#### Scenario: Terraform installed but too old
- **WHEN** `terraform version` returns < 1.5.0
- **THEN** the check SHALL report ❌ with the installed version and the minimum required

#### Scenario: Azure CLI version check
- **WHEN** `az version` is executed
- **THEN** the CLI version SHALL be compared against >= 2.60

#### Scenario: Git version check
- **WHEN** `git --version` is executed
- **THEN** the version SHALL be compared against >= 2.40

#### Scenario: Az module version check
- **WHEN** `Get-Module -ListAvailable Az` is executed
- **THEN** the module version SHALL be compared against >= 12.0

### Requirement: Azure authentication check
The script SHALL verify the operator is logged into Azure with an active subscription.

#### Scenario: Authenticated with subscription
- **WHEN** `az account show` succeeds
- **THEN** the check SHALL report ✅ with the subscription name

#### Scenario: Not authenticated
- **WHEN** `az account show` fails
- **THEN** the check SHALL report ❌ NOT LOGGED IN

### Requirement: Resource provider status check
The script SHALL check registration status of Microsoft.Compute, Microsoft.VirtualMachineImages, Microsoft.Network, and Microsoft.ManagedIdentity.

#### Scenario: Provider registered
- **WHEN** the provider RegistrationState is "Registered"
- **THEN** the check SHALL report ✅

#### Scenario: Provider not registered
- **WHEN** the provider RegistrationState is not "Registered"
- **THEN** the check SHALL report ❌ with the current state

### Requirement: Terraform init status check
The script SHALL check whether `terraform init` has been run by looking for the `.terraform/` directory.

#### Scenario: Initialized
- **WHEN** `.terraform/` exists in the terraform/ directory
- **THEN** the check SHALL report ✅

#### Scenario: Not initialized
- **WHEN** `.terraform/` does not exist
- **THEN** the check SHALL report ❌

### Requirement: Summary table output
The script SHALL output a formatted summary table showing ✅/❌ status for every check.
