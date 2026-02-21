## ADDED Requirements

### Requirement: Azure Compute Gallery creation
The system SHALL create an Azure Compute Gallery with an alphanumeric-only name within the designated resource group and location.

#### Scenario: Gallery created successfully
- **WHEN** `terraform apply` is executed with valid `gallery_name`, `resource_group_name`, and `location`
- **THEN** an Azure Compute Gallery resource is created with the specified name, tagged with the standard tag set

### Requirement: Windows 365-compliant image definition
The system SHALL create an image definition within the gallery that meets all Windows 365 ACG import requirements: Hyper-V Generation V2, x64 architecture, OS type Windows, and all five mandatory feature flags.

#### Scenario: Image definition with all W365 feature flags
- **WHEN** the image definition is created
- **THEN** it SHALL include SecurityType=TrustedLaunchSupported, IsHibernateSupported=True, DiskControllerTypes=SCSI,NVMe, IsAcceleratedNetworkSupported=True, and IsSecureBootSupported=True

#### Scenario: Image definition with custom publisher/offer/sku
- **WHEN** `image_publisher`, `image_offer`, and `image_sku` variables are provided
- **THEN** the image definition identifier block SHALL use those exact values

### Requirement: Gallery name validation
The system SHALL validate that the gallery name contains only alphanumeric characters (no hyphens or special characters).

#### Scenario: Invalid gallery name rejected
- **WHEN** a gallery name containing hyphens or special characters is provided
- **THEN** Terraform SHALL reject the input with a validation error before any API calls are made
