output "managed_identity_id" {
  description = "AIB managed identity resource ID"
  value       = azurerm_user_assigned_identity.aib.id
}

output "managed_identity_principal_id" {
  description = "AIB managed identity principal ID"
  value       = azurerm_user_assigned_identity.aib.principal_id
}
