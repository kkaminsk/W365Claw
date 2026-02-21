## 1. Timestamp and URL Fixes (High Severity)

- [x] 1.1 Add `time_static.build_time` resource to `modules/image-builder/main.tf` — **5 min**
- [x] 1.2 Update `end_of_life_date` local to reference `time_static.build_time.rfc3339` instead of `timestamp()` — **2 min**
- [x] 1.3 Fix PowerShell 7 download URL in Phase 1 customizer: change `/latest/download/` to `/download/v7.4.7/` — **2 min**
- [x] 1.4 Optionally extract PowerShell version into `var.pwsh_version` variable for consistency with other pinned versions — **5 min**

## 2. Build Reproducibility

- [x] 2.1 Identify current VS Code installer URL in Phase 2 customizer and replace with version-pinned URL or add `var.vscode_version` — **10 min**
- [x] 2.2 Identify current GitHub Desktop installer URL in Phase 2 customizer and replace with version-pinned URL or add `var.github_desktop_version` — **5 min**
- [x] 2.3 Add new variables to `modules/image-builder/variables.tf` and root `variables.tf` with defaults — **5 min**
- [x] 2.4 Update `terraform.tfvars` with pinned version values — **2 min**

## 3. Infrastructure Safety

- [x] 3.1 Add `skip_service_principal_aad_check = true` to all four `azurerm_role_assignment` resources in `modules/identity/main.tf` — **5 min**
- [x] 3.2 Add `lifecycle { prevent_destroy = true }` to `azurerm_shared_image_gallery` in `modules/gallery/main.tf` — **2 min**
- [x] 3.3 Add `lifecycle { prevent_destroy = true }` to `azurerm_shared_image` in `modules/gallery/main.tf` — **2 min**

## 4. Repo Hygiene

- [x] 4.1 Create `terraform/.gitignore` with entries for `*.tfstate`, `*.tfstate.backup`, `.terraform/`, and `terraform.tfvars` — **2 min**
- [x] 4.2 Remove `random` provider block from `versions.tf` — **1 min**
- [x] 4.3 Add `output "build_log_info"` to root `outputs.tf` or `modules/image-builder/outputs.tf` with AIB log location guidance — **3 min**

## 5. Validation

- [x] 5.1 Run `terraform fmt -check` to confirm formatting — **1 min**
- [x] 5.2 Run `terraform validate` to confirm syntax — **1 min**
- [x] 5.3 Run `terraform plan` to verify no unintended changes beyond the remediations — **5 min**
