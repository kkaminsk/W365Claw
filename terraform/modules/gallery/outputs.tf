output "gallery_id" {
  description = "Azure Compute Gallery resource ID"
  value       = azurerm_shared_image_gallery.this.id
}

output "image_definition_id" {
  description = "Image definition resource ID"
  value       = azurerm_shared_image.this.id
}
