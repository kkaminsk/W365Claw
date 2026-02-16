variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "resource_group_id" {
  description = "Resource group resource ID (for RBAC scope)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "gallery_id" {
  description = "Azure Compute Gallery resource ID (for RBAC scope)"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
