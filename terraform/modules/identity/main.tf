# ── User-Assigned Managed Identity for AIB ──
# AIB requires a managed identity to:
#   1. Read the source marketplace image
#   2. Write the output image version to the gallery
#   3. Create/manage the transient build VM and networking

resource "azurerm_user_assigned_identity" "aib" {
  name                = "id-aib-w365-dev"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# ── RBAC: Least-Privilege Roles ──
# Instead of broad Contributor access, assign only the specific roles
# that AIB requires to function.

# 1. Virtual Machine Contributor — allows AIB to create/manage the build VM
resource "azurerm_role_assignment" "aib_vm_contributor" {
  scope                            = var.resource_group_id
  role_definition_name             = "Virtual Machine Contributor"
  principal_id                     = azurerm_user_assigned_identity.aib.principal_id
  skip_service_principal_aad_check = true
}

# 2. Network Contributor — allows AIB to create transient networking for the build VM
resource "azurerm_role_assignment" "aib_network_contributor" {
  scope                            = var.resource_group_id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_user_assigned_identity.aib.principal_id
  skip_service_principal_aad_check = true
}

# 3. Managed Identity Operator — allows AIB to assign the identity to the build VM
resource "azurerm_role_assignment" "aib_identity_operator" {
  scope                            = var.resource_group_id
  role_definition_name             = "Managed Identity Operator"
  principal_id                     = azurerm_user_assigned_identity.aib.principal_id
  skip_service_principal_aad_check = true
}

# 4. Compute Gallery Image Contributor — allows AIB to write image versions to the gallery
resource "azurerm_role_assignment" "aib_gallery_contributor" {
  scope                            = var.gallery_id
  role_definition_name             = "Compute Gallery Image Contributor"
  principal_id                     = azurerm_user_assigned_identity.aib.principal_id
  skip_service_principal_aad_check = true
}
