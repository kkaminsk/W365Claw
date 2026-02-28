# ─── Subscription & Location ───────────────────────────────────────────────

variable "subscription_id" {
  description = "Azure subscription ID for all resources"
  type        = string
}

variable "location" {
  description = "Primary Azure region for all resources"
  type        = string
  default     = "eastus2"
}

# ─── Resource Group ────────────────────────────────────────────────────────

variable "resource_group_name" {
  description = "Resource group for image infrastructure"
  type        = string
  default     = "rg-w365-images"
}

# ─── Gallery ───────────────────────────────────────────────────────────────

variable "gallery_name" {
  description = "Azure Compute Gallery name (alphanumeric, no hyphens)"
  type        = string
  default     = "acgW365Dev"

  validation {
    condition     = can(regex("^[a-zA-Z0-9]+$", var.gallery_name))
    error_message = "Gallery name must be alphanumeric only (no hyphens or special characters)."
  }
}

variable "image_definition_name" {
  description = "Image definition name within the gallery (follows W365-W11-25H2-ENU naming convention)"
  type        = string
  default     = "W365-W11-25H2-ENU"
}

variable "image_publisher" {
  description = "Publisher identifier for the image definition"
  type        = string
  default     = "BigHatGroupInc"
}

variable "image_offer" {
  description = "Offer identifier for the image definition"
  type        = string
  default     = "W365-W11-25H2-ENU"
}

variable "image_sku" {
  description = "SKU identifier for the image definition"
  type        = string
  default     = "W11-25H2-ENT-Dev"
}

# ─── Image Version ─────────────────────────────────────────────────────────

variable "image_version" {
  description = "Semantic version for the image (Major.Minor.Patch)"
  type        = string
  default     = "1.0.0"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.image_version))
    error_message = "Image version must follow Major.Minor.Patch format (e.g., 1.0.0)."
  }
}

variable "exclude_from_latest" {
  description = "Set to true for canary/pilot versions; false for promoted production versions"
  type        = bool
  default     = true
}

variable "replica_count" {
  description = "Number of replicas per region"
  type        = number
  default     = 1
}

# ─── Build VM ──────────────────────────────────────────────────────────────

variable "build_vm_size" {
  description = "VM size for the AIB build VM"
  type        = string
  default     = "Standard_D4s_v5"
}

variable "build_timeout_minutes" {
  description = "Maximum build time in minutes"
  type        = number
  default     = 120
}

variable "os_disk_size_gb" {
  description = "OS disk size for the build VM in GB"
  type        = number
  default     = 128
}

# ─── Source Image ──────────────────────────────────────────────────────────

variable "source_image_publisher" {
  description = "Marketplace image publisher"
  type        = string
  default     = "MicrosoftWindowsDesktop"
}

variable "source_image_offer" {
  description = "Marketplace image offer"
  type        = string
  default     = "windows-11"
}

variable "source_image_sku" {
  description = "Marketplace image SKU"
  type        = string
  default     = "win11-25h2-ent"
}

variable "source_image_version" {
  description = "Marketplace image version — MUST be pinned to a specific version for build reproducibility (do not use 'latest')"
  type        = string
  default     = "26200.7840.260206"

  validation {
    condition     = var.source_image_version != "latest"
    error_message = "Source image version must be pinned to a specific version (not 'latest') for build reproducibility."
  }
}

# ─── Software Versions ────────────────────────────────────────────────────

variable "node_version" {
  description = "Node.js version to install (must be >= 22)"
  type        = string
  default     = "v24.13.1"

  validation {
    condition     = can(regex("^v(2[2-9]|[3-9][0-9])\\.\\d+\\.\\d+$", var.node_version))
    error_message = "Node.js version must be v22 or higher."
  }
}

variable "python_version" {
  description = "Python version to install"
  type        = string
  default     = "3.14.3"
}

variable "git_version" {
  description = "Git for Windows version to install"
  type        = string
  default     = "2.53.0"
}

variable "pwsh_version" {
  description = "PowerShell 7 (LTS) version to install"
  type        = string
  default     = "7.4.13"
}

variable "azure_cli_version" {
  description = "Azure CLI version to install"
  type        = string
  default     = "2.83.0"
}

# ─── Installer SHA256 Checksums ───────────────────────────────────────────
# Update these when bumping software versions. Obtain from official release pages.
# VS Code and GitHub Desktop are intentionally excluded (floating latest URLs).

variable "node_sha256" {
  description = "SHA256 checksum for the Node.js MSI installer"
  type        = string
  default     = ""
}

variable "python_sha256" {
  description = "SHA256 checksum for the Python installer"
  type        = string
  default     = ""
}

variable "pwsh_sha256" {
  description = "SHA256 checksum for the PowerShell 7 MSI installer"
  type        = string
  default     = ""
}

variable "git_sha256" {
  description = "SHA256 checksum for the Git for Windows installer"
  type        = string
  default     = ""
}

variable "azure_cli_sha256" {
  description = "SHA256 checksum for the Azure CLI MSI installer"
  type        = string
  default     = ""
}

# ─── OpenClaw Configuration ───────────────────────────────────────────────

variable "openclaw_default_model" {
  description = "Default LLM model for OpenClaw configuration template"
  type        = string
  default     = "anthropic/claude-opus-4-6"
}

variable "openclaw_gateway_port" {
  description = "Port for the OpenClaw gateway"
  type        = number
  default     = 18789
}

# ─── Agent Skills & MCP Servers ────────────────────────────────────────────

variable "skills_repo_url" {
  description = "Git URL for the curated agent skills repository (empty to skip skills pre-seeding)"
  type        = string
  default     = ""
}

# ─── Tags ──────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    workload   = "Windows365"
    purpose    = "DeveloperImages"
    managed_by = "PlatformEngineering"
    iac        = "Terraform"
  }
}
