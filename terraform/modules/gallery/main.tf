resource "azurerm_shared_image_gallery" "this" {
  name                = var.gallery_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_shared_image" "this" {
  name                = var.image_definition_name
  gallery_name        = azurerm_shared_image_gallery.this.name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Windows"
  hyper_v_generation  = "V2"
  architecture        = "x64"

  identifier {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
  }

  # ── Windows 365 ACG Import Requirements ──
  # These feature flags are mandatory for Windows 365 ingestion.
  # azurerm v4 replaced features {} blocks with top-level arguments.
  trusted_launch_supported             = true
  hibernation_enabled                  = true
  disk_controller_type_nvme_enabled    = true
  accelerated_network_support_enabled  = true

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}
