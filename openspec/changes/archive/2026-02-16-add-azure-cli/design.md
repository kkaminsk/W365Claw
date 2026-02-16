## Context

The W365Claw image build uses Azure VM Image Builder with inline PowerShell customizers organized in four phases: Core Runtimes (Phase 1), Developer Tools (Phase 2), AI Agents (Phase 3), and Configuration & Policy (Phase 4). All software is version-pinned via Terraform variables, downloaded with a retry helper, installed silently via MSI/EXE, and verified post-install.

Azure CLI is not currently included. Developers must install it manually after provisioning, which breaks the "ready to code on first login" goal.

## Goals / Non-Goals

**Goals:**
- Ship Azure CLI pre-installed in the W365 developer image at a pinned version
- Follow the exact same patterns as existing Phase 2 tools (MSI download, retry, exit-code check, PATH refresh, verify)
- Include Azure CLI in the SBOM and validation checklist

**Non-Goals:**
- Configuring Azure CLI defaults or extensions in the image (users configure their own `az` preferences post-login)
- Replacing the Az PowerShell module with Azure CLI for project automation (the "PowerShell everywhere" convention remains)
- Adding `az login` or credential bootstrapping to Active Setup

## Decisions

### 1. Install in Phase 2 (Developer Tools), not Phase 1 or 3

Azure CLI is a developer tool alongside VS Code, Git, and GitHub Desktop. It has no dependency on Node.js or Python (Phase 1 outputs) and is not an AI agent (Phase 3). Placing it at the end of Phase 2 keeps the logical grouping clean and requires no new build phases or restarts.

**Alternative considered**: Dedicated Phase 2.5 or new phase. Rejected — adds a restart cycle for no benefit and breaks the existing 4-phase structure.

### 2. MSI installer via azcliprod CDN

The Azure CLI MSI is available from `azcliprod.blob.core.windows.net/msi/azure-cli-<version>-x64.msi`. This is the official Microsoft CDN for Azure CLI releases.

**Alternative considered**: `winget install Microsoft.AzureCLI`. Rejected — the build VM runs as SYSTEM in a non-interactive AIB session where winget may not be available or configured. Direct MSI download is more reliable and matches the pattern used by every other tool in the build.

### 3. Version pinned via Terraform variable

A new `azure_cli_version` variable (default `2.83.0`) follows the existing pattern for `git_version`, `pwsh_version`, etc. The version flows: `variables.tf` → `main.tf` root module → `image-builder` module → inline PowerShell interpolation.

**Alternative considered**: Use `latest` tag or `aka.ms/installazurecliwindowsx64` redirect. Rejected — violates the project's pinned-version convention and breaks build reproducibility.

### 4. Verify with first line of `az --version`

`az --version` outputs multiple lines (CLI version, extensions, Python version, etc.). Capturing only the first line via `Select-Object -First 1` gives a clean single-line verification in the build log, matching the terse `[VERIFY]` pattern of other tools.

## Risks / Trade-offs

- **Image size increase (~500 MB)** → Acceptable trade-off for developer productivity. The 128 GB OS disk has ample headroom.
- **CDN availability during build** → Mitigated by the existing `Get-InstallerWithRetry` helper (3 attempts, 10-second backoff).
- **Azure CLI auto-update prompts** → Azure CLI does not auto-update on Windows when installed via MSI. No mitigation needed.
- **Version drift across images** → Mitigated by pinned version variable. Operators bump `azure_cli_version` in `terraform.tfvars` when building new image versions.

## Open Questions

None — this is a straightforward additive change following established patterns.
