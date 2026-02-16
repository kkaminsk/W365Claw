## 1. Project Scaffolding

- [ ] 1.1 Create `terraform/` directory structure with root and three module directories (gallery, identity, image-builder)
- [ ] 1.2 Create `versions.tf` with provider constraints (azurerm ~> 4.0, azapi ~> 2.0, random ~> 3.6, time ~> 0.11) and local backend
- [ ] 1.3 Create root `variables.tf` with all input variables including validations (gallery name alphanumeric, image version semver, source version not "latest", node version >= 22)
- [ ] 1.4 Create `terraform.tfvars` example with all default values

## 2. Gallery Module

- [ ] 2.1 Create `modules/gallery/main.tf` with `azurerm_shared_image_gallery` and `azurerm_shared_image` resources
- [ ] 2.2 Implement all five Windows 365 feature flags (SecurityType, IsHibernateSupported, DiskControllerTypes, IsAcceleratedNetworkSupported, IsSecureBootSupported)
- [ ] 2.3 Create `modules/gallery/variables.tf` with gallery_name, image_definition_name, image_publisher, image_offer, image_sku, resource_group_name, location, tags
- [ ] 2.4 Create `modules/gallery/outputs.tf` exposing gallery_id and image_definition_id

## 3. Identity Module

- [ ] 3.1 Create `modules/identity/main.tf` with user-assigned managed identity (`id-aib-w365-dev`)
- [ ] 3.2 Implement four RBAC role assignments: VM Contributor, Network Contributor, Managed Identity Operator (RG scope), Compute Gallery Image Contributor (gallery scope)
- [ ] 3.3 Create `modules/identity/variables.tf` with resource_group_name, resource_group_id, location, gallery_id, tags
- [ ] 3.4 Create `modules/identity/outputs.tf` exposing managed_identity_id and managed_identity_principal_id

## 4. Image Builder Module

- [ ] 4.1 Create `modules/image-builder/main.tf` with locals for template_name, end_of_life_date, customizers, distribute, and vm_profile
- [ ] 4.2 Implement Phase 1 customizer: Node.js, Python, PowerShell 7 installation with retry logic and verification
- [ ] 4.3 Implement Phase 2 customizer: VS Code, Git, GitHub Desktop installation
- [ ] 4.4 Implement Phase 3 customizer: OpenClaw, Claude Code npm install, npm audit gate, SBOM generation
- [ ] 4.5 Implement Phase 4 customizer: Claude Code managed settings, OpenClaw template config, Active Setup registration, Teams VDI, cleanup
- [ ] 4.6 Add WindowsUpdate and WindowsRestart customizers between phases
- [ ] 4.7 Create `azapi_resource` for image template with identity, source, customizers, distribute, vmProfile
- [ ] 4.8 Create `azapi_resource_action` to trigger the build with appropriate timeout
- [ ] 4.9 Create `modules/image-builder/variables.tf` with all consumed variables
- [ ] 4.10 Create `modules/image-builder/outputs.tf` exposing template_name

## 5. Root Module Integration

- [ ] 5.1 Create root `main.tf` with resource group and three module calls (gallery, identity, image-builder) with proper dependency wiring
- [ ] 5.2 Create root `outputs.tf` with gallery_id, image_definition_id, managed_identity_id, managed_identity_principal_id, image_template_name, and next_steps guide

## 6. Validation & Audit

- [ ] 6.1 Run `terraform fmt -check` to verify HCL formatting
- [ ] 6.2 Run `terraform validate` to check configuration syntax
- [ ] 6.3 Perform engineering audit covering security, maintainability, cost, and W365 compliance
- [ ] 6.4 Write TerraformAudit.md with findings and recommendations
