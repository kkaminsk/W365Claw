variable "resource_group_id" {
  description = "Resource group resource ID"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "managed_identity_id" {
  description = "User-assigned managed identity resource ID for AIB"
  type        = string
}

variable "image_definition_id" {
  description = "Image definition resource ID in the gallery"
  type        = string
}

variable "image_version" {
  description = "Semantic version for the image (Major.Minor.Patch)"
  type        = string
}

variable "exclude_from_latest" {
  description = "Exclude this version from latest"
  type        = bool
}

variable "replica_count" {
  description = "Number of replicas per region"
  type        = number
}

variable "build_vm_size" {
  description = "VM size for the AIB build VM"
  type        = string
}

variable "build_timeout_minutes" {
  description = "Maximum build time in minutes"
  type        = number
}

variable "os_disk_size_gb" {
  description = "OS disk size for the build VM in GB"
  type        = number
}

variable "source_image_publisher" {
  description = "Marketplace image publisher"
  type        = string
}

variable "source_image_offer" {
  description = "Marketplace image offer"
  type        = string
}

variable "source_image_sku" {
  description = "Marketplace image SKU"
  type        = string
}

variable "source_image_version" {
  description = "Marketplace image version (pinned)"
  type        = string
}

variable "node_version" {
  description = "Node.js version to install"
  type        = string
}

variable "python_version" {
  description = "Python version to install"
  type        = string
}

variable "git_version" {
  description = "Git for Windows version to install"
  type        = string
}

variable "pwsh_version" {
  description = "PowerShell 7 version to install"
  type        = string
}

variable "openclaw_version" {
  description = "OpenClaw npm package version"
  type        = string
}

variable "claude_code_version" {
  description = "Claude Code npm package version"
  type        = string
}

variable "openspec_version" {
  description = "OpenSpec npm package version"
  type        = string
}

variable "openclaw_default_model" {
  description = "Default LLM model for OpenClaw"
  type        = string
}

variable "openclaw_gateway_port" {
  description = "Port for the OpenClaw gateway"
  type        = number
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
