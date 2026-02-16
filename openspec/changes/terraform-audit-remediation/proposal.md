## Why

An automated engineering audit ([TerraformAudit.md](../../../TerraformAudit.md)) of the W365Claw Terraform solution identified 11 issues across high, medium, and low severity. Two high-severity issues — perpetual diff from `timestamp()` and a fragile PowerShell 7 download URL — risk build failures in production. Medium issues affect reproducibility, safety, and operational hygiene. This change proposal remediates all actionable findings to bring the solution to full production readiness.

## What Changes

- **Fix**: Replace `timestamp()` with `time_static` resource to eliminate perpetual diff on image template (H1)
- **Fix**: Correct PowerShell 7 download URL to use a pinned release path instead of `/latest/` (H2)
- **Fix**: Pin VS Code and GitHub Desktop installer versions for reproducible builds (M4, M5)
- **Fix**: Add `skip_service_principal_aad_check = true` to all RBAC role assignments to prevent race conditions (M2)
- **Fix**: Add `lifecycle { prevent_destroy = true }` to gallery and image definition resources (M3)
- **New**: Add `.gitignore` to exclude state files, `.terraform/`, and `terraform.tfvars` (M1)
- **Fix**: Remove unused `random` provider declaration (L1)
- **New**: Add Terraform output for build log location (L4)

## Capabilities

### Modified Capabilities
- `timestamp-and-urls`: Fixes the two high-severity issues — deterministic build timestamps and reliable installer URLs
- `build-reproducibility`: Pins VS Code and GitHub Desktop versions to produce identical images across builds
- `infrastructure-safety`: Hardens identity and gallery resources against race conditions and accidental deletion
- `repo-hygiene`: Cleans up unused declarations, adds gitignore, and surfaces build log output

## Impact

- **Risk reduction**: Eliminates two high-severity build-breaking issues and three medium-severity reliability gaps
- **Breaking changes**: None — all changes are additive or corrective; existing state is compatible
- **Effort**: ~40 minutes total across all remediations
- **Dependencies**: No new provider or module dependencies
