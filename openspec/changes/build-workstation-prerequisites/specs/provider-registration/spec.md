## ADDED Requirements

### Requirement: Register missing Azure resource providers
The script SHALL register any of the four required resource providers that are not in "Registered" state.

#### Scenario: Provider not registered
- **WHEN** `Microsoft.VirtualMachineImages` RegistrationState is "NotRegistered"
- **THEN** `az provider register --namespace Microsoft.VirtualMachineImages` SHALL be executed

#### Scenario: Provider already registered
- **WHEN** a provider is already "Registered"
- **THEN** the script SHALL skip registration for that provider

### Requirement: Wait for registration with timeout
The script SHALL poll registration status every 10 seconds until the provider reaches "Registered" state, with a 5-minute timeout per provider.

#### Scenario: Registration succeeds within timeout
- **WHEN** the provider reaches "Registered" within 5 minutes
- **THEN** the check SHALL report ✅

#### Scenario: Registration times out
- **WHEN** the provider does not reach "Registered" within 5 minutes
- **THEN** the check SHALL report ❌ TIMEOUT and the script SHALL continue with remaining providers

### Requirement: All four providers checked
The script SHALL check and register if needed:
1. `Microsoft.Compute`
2. `Microsoft.VirtualMachineImages`
3. `Microsoft.Network`
4. `Microsoft.ManagedIdentity`
