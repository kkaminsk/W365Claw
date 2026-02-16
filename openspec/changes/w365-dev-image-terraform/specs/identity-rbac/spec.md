## ADDED Requirements

### Requirement: User-assigned managed identity for AIB
The system SHALL create a user-assigned managed identity dedicated to Azure Image Builder operations.

#### Scenario: Identity created in resource group
- **WHEN** `terraform apply` is executed
- **THEN** a user-assigned managed identity named `id-aib-w365-dev` is created in the specified resource group and location

### Requirement: Least-privilege RBAC assignments
The system SHALL assign exactly four RBAC roles to the managed identity, scoped as narrowly as possible: Virtual Machine Contributor, Network Contributor, and Managed Identity Operator at resource group scope, and Compute Gallery Image Contributor at gallery scope.

#### Scenario: Resource group-scoped roles assigned
- **WHEN** the managed identity is created
- **THEN** Virtual Machine Contributor, Network Contributor, and Managed Identity Operator roles SHALL be assigned at the resource group scope

#### Scenario: Gallery-scoped role assigned
- **WHEN** the managed identity is created and the gallery exists
- **THEN** Compute Gallery Image Contributor SHALL be assigned scoped to the gallery resource only (not the resource group)

### Requirement: No broad Contributor access
The system SHALL NOT assign the Contributor built-in role or any Owner-level role to the AIB identity.

#### Scenario: Overly broad role rejected
- **WHEN** reviewing the Terraform configuration
- **THEN** no role assignment SHALL use `Contributor` or `Owner` as the role_definition_name
