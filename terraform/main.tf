resource "azurerm_resource_group" "images" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ── Azure Compute Gallery ──
module "gallery" {
  source = "./modules/gallery"

  resource_group_name   = azurerm_resource_group.images.name
  location              = var.location
  gallery_name          = var.gallery_name
  image_definition_name = var.image_definition_name
  image_publisher       = var.image_publisher
  image_offer           = var.image_offer
  image_sku             = var.image_sku
  tags                  = var.tags
}

# ── Managed Identity + RBAC ──
module "identity" {
  source = "./modules/identity"

  resource_group_name = azurerm_resource_group.images.name
  resource_group_id   = azurerm_resource_group.images.id
  location            = var.location
  gallery_id          = module.gallery.gallery_id
  tags                = var.tags
}

# ── Image Builder ──
module "image_builder" {
  source = "./modules/image-builder"

  resource_group_id      = azurerm_resource_group.images.id
  location               = var.location
  managed_identity_id    = module.identity.managed_identity_id
  image_definition_id    = module.gallery.image_definition_id
  image_version          = var.image_version
  exclude_from_latest    = var.exclude_from_latest
  replica_count          = var.replica_count
  build_vm_size          = var.build_vm_size
  build_timeout_minutes  = var.build_timeout_minutes
  os_disk_size_gb        = var.os_disk_size_gb
  source_image_publisher = var.source_image_publisher
  source_image_offer     = var.source_image_offer
  source_image_sku       = var.source_image_sku
  source_image_version   = var.source_image_version
  node_version           = var.node_version
  python_version         = var.python_version
  git_version            = var.git_version
  pwsh_version           = var.pwsh_version
  vscode_version         = var.vscode_version
  github_desktop_version = var.github_desktop_version
  openclaw_version       = var.openclaw_version
  claude_code_version    = var.claude_code_version
  openclaw_default_model = var.openclaw_default_model
  openclaw_gateway_port  = var.openclaw_gateway_port
  tags                   = var.tags
}
