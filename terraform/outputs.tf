output "gallery_id" {
  description = "Azure Compute Gallery resource ID"
  value       = module.gallery.gallery_id
}

output "image_definition_id" {
  description = "Image definition resource ID"
  value       = module.gallery.image_definition_id
}

output "managed_identity_id" {
  description = "AIB managed identity resource ID"
  value       = module.identity.managed_identity_id
}

output "managed_identity_principal_id" {
  description = "AIB managed identity principal ID (for additional RBAC)"
  value       = module.identity.managed_identity_principal_id
}

output "image_template_name" {
  description = "AIB image template name"
  value       = module.image_builder.template_name
}

output "build_log_info" {
  description = "Where to find AIB build logs"
  value       = "Azure Portal > Image Templates > ${module.image_builder.template_name} > Logs (or run: Get-AzImageBuilderTemplate -Name '${module.image_builder.template_name}' -ResourceGroupName '${var.resource_group_name}' | Select-Object -ExpandProperty LastRunStatus)"
}

output "next_steps" {
  description = "Manual steps required after Terraform apply"
  value       = <<-EOT

    ══════════════════════════════════════════════════════════════════
    IMAGE BUILD COMPLETE — NEXT STEPS
    ══════════════════════════════════════════════════════════════════

    1. VERIFY IMAGE VERSION
       Get-AzGalleryImageVersion `
         -ResourceGroupName "${var.resource_group_name}" `
         -GalleryName "${var.gallery_name}" `
         -GalleryImageDefinitionName "${var.image_definition_name}" |
         Format-Table Name, ProvisioningState, PublishingProfile

    2. TEAR DOWN BUILD INFRASTRUCTURE (cost optimization)
       Keep only the gallery and image — destroy everything else:
       terraform destroy

       NOTE: The image version persists in the gallery independently
       of the AIB template and other build resources.

    3. IMPORT INTO WINDOWS 365 (Portal)
       Intune > Devices > Windows 365 > Custom images > Add
       > Azure Compute Gallery
       > Select: ${var.gallery_name} / ${var.image_definition_name} / ${var.image_version}

    4. CREATE/UPDATE PROVISIONING POLICY
       Assign the imported image to a provisioning policy
       targeting your developer security group.

    5. USER CONFIGURATION (post-login)
       Each user manages their own ANTHROPIC_API_KEY:
       - Set as user environment variable, or
       - Configure via OpenClaw settings

    6. PROMOTE (when validated)
       Set exclude_from_latest = false and re-apply:
       terraform apply -var='exclude_from_latest=false'

    ══════════════════════════════════════════════════════════════════
  EOT
}
