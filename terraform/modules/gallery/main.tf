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
  # All five features are mandatory for Windows 365 ingestion.
  # Missing any one will cause the import to fail.

  features {
    name  = "SecurityType"
    value = "TrustedLaunchSupported"
  }

  features {
    name  = "IsHibernateSupported"
    value = "True"
  }

  features {
    name  = "DiskControllerTypes"
    value = "SCSI,NVMe"
  }

  features {
    name  = "IsAcceleratedNetworkSupported"
    value = "True"
  }

  features {
    name  = "IsSecureBootSupported"
    value = "True"
  }

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}
