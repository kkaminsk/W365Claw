## 1. Script Scaffolding

- [x] 1.1 Create `scripts/` directory
- [x] 1.2 Create `scripts/Initialize-BuildWorkstation.ps1` with param block (`-Force` switch, `-TerraformDir` path defaulting to `$PSScriptRoot\..\terraform`)

## 2. Pre-Flight Checks (Phase 1)

- [x] 2.1 Implement OS validation (Windows 10/11 x64)
- [x] 2.2 Implement Administrator privilege check
- [x] 2.3 Implement `Test-Tool` helper function (runs command, parses version, compares against minimum)
- [x] 2.4 Implement Terraform version check (>= 1.5.0)
- [x] 2.5 Implement Azure CLI version check (>= 2.60)
- [x] 2.6 Implement Git version check (>= 2.40)
- [x] 2.7 Implement Az PowerShell module version check (>= 12.0)
- [x] 2.8 Implement Azure authentication check (`az account show`)
- [x] 2.9 Implement resource provider status check (4 providers)
- [x] 2.10 Implement terraform init status check (`.terraform/` directory)
- [x] 2.11 Implement summary table output with ✅/❌ formatting

## 3. Installation (Phase 2)

- [x] 3.1 Implement `Install-WithWinget` helper function (winget install with fallback detection)
- [x] 3.2 Implement confirmation prompt logic (skip when `-Force`)
- [x] 3.3 Implement Terraform installation (winget primary, ZIP fallback with PATH addition)
- [x] 3.4 Implement Azure CLI installation (winget)
- [x] 3.5 Implement Git installation (winget)
- [x] 3.6 Implement Az module installation (Install-Module with PSGallery trust)
- [x] 3.7 Implement Azure login flow (`az login` + subscription selection)
- [x] 3.8 Implement resource provider registration with 10-second polling and 5-minute timeout
- [x] 3.9 Implement `terraform init` execution when `.terraform/` missing
- [x] 3.10 Implement PATH refresh after each tool installation

## 4. Post-Installation Verification (Phase 3)

- [x] 4.1 Re-run all pre-flight checks
- [x] 4.2 Output final summary table
- [x] 4.3 Set exit code (0 = all pass, 1 = failures remain)

## 5. Documentation

- [x] 5.1 Add "Getting Started" section to README.md referencing the script
- [x] 5.2 Add inline help/comments in the script

## 6. Validation

- [x] 6.1 Verify script runs without error on a machine with all prerequisites already installed (idempotent no-op)
- [x] 6.2 Verify script works in both Windows PowerShell 5.1 and PowerShell 7+
