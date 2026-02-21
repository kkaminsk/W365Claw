## Why

The README heavily documents `Initialize-TerraformVars.ps1` — referenced in the file tree (line 712), build instructions (line 1695), and multiple walkthrough chapters (lines 1910, 1916, 3451, 3549). This script does not exist in the repository. Only `Initialize-BuildWorkstation.ps1` and `Teardown-BuildResources.ps1` are present.

This is the single biggest gap: the book's build workflow is broken as written because it tells readers to run a script that doesn't exist.

## What Changes

- **Create `scripts/Initialize-TerraformVars.ps1`** — an interactive script that:
  1. Auto-detects latest versions of all pinned packages (Node.js, Python, PowerShell 7, Git, Azure CLI, OpenClaw, Claude Code, OpenSpec, Codex CLI)
  2. Fetches SHA256 checksums for MSI/exe installers
  3. Queries Azure marketplace for latest Windows 11 image version
  4. Detects current Azure subscription context
  5. Writes/updates `terraform/terraform.tfvars` with all detected values
  6. Presents a summary for operator review before writing

## Capabilities

### New Capabilities
- `tfvars-automation`: Automated detection and population of all Terraform input variables

## Impact

- **New script** — no existing code modified
- Unblocks the entire build workflow documented in the README
