## MODIFIED Requirements

### Requirement: RBAC role assignments tolerate AAD propagation delay (M2)
The system SHALL set `skip_service_principal_aad_check = true` on all role assignments to prevent intermittent failures when the managed identity principal has not yet propagated in Azure AD.

#### Problem
`modules/identity/main.tf` creates a managed identity and assigns RBAC roles in the same apply. Azure AD principal propagation is eventually consistent — the role assignment may fail with a "principal not found" error on first apply.

#### Fix
Add the flag to each of the four `azurerm_role_assignment` resources:

**File:** `modules/identity/main.tf`

```hcl
# Apply to all four role assignments (VM Contributor, Network Contributor,
# Managed Identity Operator, Compute Gallery Image Contributor)

resource "azurerm_role_assignment" "vm_contributor" {
  scope                            = var.resource_group_id
  role_definition_name             = "Virtual Machine Contributor"
  principal_id                     = azurerm_user_assigned_identity.aib.principal_id
  skip_service_principal_aad_check = true  # ADD THIS LINE
}

# Repeat for the other three role assignments
```

#### Scenario: First-time apply succeeds without retry
- **WHEN** `terraform apply` is run on a fresh environment with no prior state
- **THEN** all four role assignments SHALL succeed without "principal not found" errors

---

### Requirement: Gallery and image definition protected from accidental deletion (M3)
The system SHALL use `lifecycle { prevent_destroy = true }` on the gallery and image definition resources to guard against accidental `terraform destroy` deleting stored image versions.

#### Problem
`modules/gallery/main.tf` has no lifecycle protection. Running `terraform destroy` (even accidentally) will delete the gallery and all image versions it contains. While the spec calls for infra teardown after build, the gallery must persist to serve images to Windows 365 provisioning.

#### Fix

**File:** `modules/gallery/main.tf`

```hcl
resource "azurerm_shared_image_gallery" "gallery" {
  name                = var.gallery_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_shared_image" "image" {
  name                = var.image_definition_name
  gallery_name        = azurerm_shared_image_gallery.gallery.name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Windows"
  hyper_v_generation  = "V2"
  architecture        = "x64"

  # ... existing feature flags and identifier block ...

  lifecycle {
    prevent_destroy = true
  }
}
```

#### Scenario: Destroy blocked on gallery resources
- **WHEN** `terraform destroy` is run
- **THEN** Terraform SHALL exit with an error refusing to destroy the gallery and image definition resources
- **AND** all other resources (identity, AIB template, resource group) SHALL still be destroyable
