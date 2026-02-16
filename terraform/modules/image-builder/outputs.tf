output "template_name" {
  description = "AIB image template name"
  value       = azapi_resource.image_template.name
}

output "template_id" {
  description = "AIB image template resource ID"
  value       = azapi_resource.image_template.id
}
