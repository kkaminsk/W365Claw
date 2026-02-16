# CLAUDE.md

Project context for AI coding agents (Claude Code, OpenClaw, etc.)

## Project Overview

W365Claw builds Windows 365 developer images using Terraform and Azure VM Image Builder. The images ship pre-loaded with OpenClaw, Claude Code, and a full dev toolchain.

## Tech Stack

- **IaC:** Terraform (HCL) with `azurerm`, `azapi`, and `time` providers
- **Cloud:** Azure — Compute Gallery, VM Image Builder, Managed Identity, RBAC
- **Scripts:** Inline PowerShell in AIB customizers (no external script storage)
- **Docs:** Markdown specs following the OpenSpec change proposal format

## Key Conventions

- **PowerShell everywhere.** No Azure CLI (`az`), no bash. All commands, scripts, and documentation use PowerShell and the `Az` module.
- **Pinned versions.** All software (Node.js, Python, Git, PowerShell 7, VS Code, GitHub Desktop, OpenClaw, Claude Code) is version-pinned via Terraform variables.
- **Least-privilege RBAC.** The AIB managed identity gets exactly 4 roles — no Contributor or Owner.
- **Inline scripts only.** No storage accounts or external script URIs. Everything is embedded in the AIB template.
- **Teardown after build.** All infra is ephemeral except the gallery image version.

## Directory Layout

- `terraform/` — Root module + 3 child modules (gallery, identity, image-builder)
- `terraform/terraform.tfvars` — Environment values (git-ignored, contains subscription_id)
- `openspec/` — Change proposals following spec-driven format
- `TerraformApplicationSpecification.md` — Full spec with all HCL and operational runbook
- `TerraformAudit.md` — Engineering audit findings and remediation

## Module Structure

- **gallery** — `azurerm_shared_image_gallery` + `azurerm_shared_image` with W365 feature flags and `prevent_destroy`
- **identity** — `azurerm_user_assigned_identity` + 4 role assignments with `skip_service_principal_aad_check`
- **image-builder** — `azapi_resource` for AIB template + `azapi_resource_action` to trigger build; uses `time_static` for end-of-life date

## Things to Watch

- `time_static.build_time` captures build timestamp once in state — don't replace with `timestamp()`
- Gallery and image definition have `lifecycle { prevent_destroy = true }` — intentional
- PowerShell helper functions (`Update-SessionEnvironment`, `Get-InstallerWithRetry`) are duplicated across phases (inline scripts can't share code) — document changes in all phases
- The `random` provider was intentionally removed — don't re-add unless needed
