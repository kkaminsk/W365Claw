variable "gallery_name" {
  description = "Azure Compute Gallery name"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "image_definition_name" {
  description = "Image definition name"
  type        = string
}

variable "image_publisher" {
  description = "Publisher identifier"
  type        = string
}

variable "image_offer" {
  description = "Offer identifier"
  type        = string
}

variable "image_sku" {
  description = "SKU identifier"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
