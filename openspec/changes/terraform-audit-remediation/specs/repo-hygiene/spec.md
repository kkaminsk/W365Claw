## ADDED Requirements

### Requirement: Git-ignored sensitive and generated files (M1)
The repository SHALL include a `.gitignore` file that excludes Terraform state, provider cache, and variable files containing secrets.

#### Problem
`terraform.tfvars` contains `subscription_id` and is not excluded from version control. No `.gitignore` exists in the `terraform/` directory.

#### Fix
Create `terraform/.gitignore`:

```gitignore
# Terraform state
*.tfstate
*.tfstate.backup

# Provider cache
.terraform/

# Variable files with secrets
terraform.tfvars

# Crash logs
crash.log
crash.*.log

# Lock file (optional — include if you want provider pinning in VCS)
# .terraform.lock.hcl
```

#### Scenario: Sensitive files excluded from commits
- **WHEN** a developer runs `git status` in the `terraform/` directory
- **THEN** `terraform.tfvars`, `*.tfstate`, and `.terraform/` SHALL NOT appear as untracked or modified files

---

## MODIFIED Requirements

### Requirement: No unused provider declarations (L1)
The system SHALL only declare providers that are actively used, to minimise `terraform init` time and avoid confusion.

#### Problem
`versions.tf` declares the `random` provider (`hashicorp/random ~> 3.6`) but no resource or data source in any module uses it.

#### Fix
Remove the unused provider block:

**File:** `versions.tf`

```hcl
# REMOVE this block:
random = {
  source  = "hashicorp/random"
  version = "~> 3.6"
}
```

#### Scenario: No unused providers after init
- **WHEN** `terraform init` is run
- **THEN** only `azurerm`, `azapi`, and `time` providers SHALL be downloaded

---

### Requirement: Build log output for operational visibility (L4)
The system SHALL expose a Terraform output that tells the operator where to find Azure Image Builder build logs after a build completes.

#### Problem
After `azapi_resource_action.run_build` completes, there is no output indicating where to review build logs or troubleshoot failures.

#### Fix
Add an output to the root module:

**File:** `outputs.tf` (root module)

```hcl
output "build_log_info" {
  description = "Where to find Azure Image Builder build logs"
  value       = <<-EOT
    Build logs are available in the Azure Portal:
    Portal > Resource Groups > ${var.resource_group_name} > Image Templates > ${module.image_builder.template_name} > Logs

    Or via PowerShell:
    Get-AzImageBuilderTemplate -Name ${module.image_builder.template_name} -ResourceGroupName ${var.resource_group_name} | Select-Object -ExpandProperty LastRunStatus
  EOT
}
```

#### Scenario: Operator can locate build logs
- **WHEN** `terraform apply` completes successfully
- **THEN** the `build_log_info` output SHALL display the portal path and CLI command to access AIB logs
