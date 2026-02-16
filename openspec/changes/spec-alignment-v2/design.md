## Approach

Surgical edits across 4 files (root `variables.tf`, root `main.tf`, `modules/image-builder/variables.tf`, `modules/image-builder/main.tf`) plus `terraform.tfvars`. No structural changes — same module layout, same phases, same patterns.

## Key Decisions

### VS Code: Latest stable URL instead of pinned version
- **Before**: `https://update.code.visualstudio.com/$VSCodeVersion/win32-x64/stable` (pinned)
- **After**: `https://update.code.visualstudio.com/latest/win32-x64-system/stable` (latest + system installer)
- **Why**: Spec explicitly uses `/latest/`. VS Code auto-updates anyway post-deployment. The `win32-x64-system` variant (not `win32-x64`) is correct for machine-wide installation.

### GitHub Desktop: Central provisioner URL instead of release-pinned
- **Before**: `https://github.com/desktop/desktop/releases/download/release-$GHDesktopVersion/GitHubDesktopSetup-x64.msi`
- **After**: `https://central.github.com/deployments/desktop/desktop/latest/GitHubDesktopSetup-x64.msi`
- **Why**: Spec uses the central provisioner URL. GitHub Desktop also auto-updates. The central URL is more reliable than constructing release URLs.

### OpenSpec added to Phase 3 (not a new phase)
- Installs between Claude Code and npm audit
- Same pattern: `npm install -g`, `Update-SessionEnvironment`, `Get-Command` verification
- npm audit covers OpenSpec along with the other global packages

### SBOM manifest gains two fields
- `pwshVersion` and `openspecVersion` added to the software manifest JSON
- Matches spec's manifest structure

## What Not to Change

- **`random` provider**: Spec includes it; CLAUDE.md explicitly says don't re-add. Code is correct.
- **`build_log_info` output**: Code has it; spec doesn't. Keep it — it's useful.
- **`time_static` pattern**: Code uses it correctly to avoid perpetual diffs. Spec uses `timestamp()` which would cause diffs on every plan. Code is better.
- **`prevent_destroy` lifecycle**: Code has it on gallery resources; spec doesn't mention it. Keep it — it's a safety net.
- **`skip_service_principal_aad_check`**: Code has it on role assignments; spec doesn't. Keep it — avoids race conditions.
