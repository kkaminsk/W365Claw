## Why

The `TerraformApplicationSpecification.md` has been updated with new requirements (OpenSpec installation, updated software versions, simplified download URLs) that the current Terraform code doesn't yet reflect. This change aligns the code with the spec to ensure the built image matches the documented target state.

## What Changes

- **Add**: OpenSpec (`@fission-ai/openspec`) installation in Phase 3 (AI Agents) with version variable
- **Update**: Software version defaults to match spec — Node.js v24.13.1, Python 3.14.3, Git 2.53.0, PowerShell 7.4.13
- **Remove**: `vscode_version` and `github_desktop_version` variables — switch to "latest stable" download URLs per spec (VS Code uses `/latest/win32-x64-system/stable`, GitHub Desktop uses central.github.com MSI)
- **Update**: SBOM software manifest to include `pwshVersion` and `openspecVersion` fields
- **Keep**: `random` provider correctly excluded (spec erroneously includes it; CLAUDE.md says don't re-add)
- **Keep**: `build_log_info` output (code has it, spec omits it — code is better)

## Capabilities

### Modified Capabilities
- `image-builder-customizers`: Phase 3 gains OpenSpec installation; Phase 2 download URLs simplified to "latest stable"
- `software-versioning`: Default versions bumped; two version-pin variables removed in favor of latest-stable downloads

## Impact

- **Variables**: +1 (`openspec_version`), -2 (`vscode_version`, `github_desktop_version`) = net -1 variable
- **Module interfaces**: `image-builder` module loses `vscode_version` and `github_desktop_version` inputs, gains `openspec_version`
- **Risk**: VS Code and GitHub Desktop will no longer be version-pinned — each image build gets the current latest. This trades reproducibility for always-current tooling. Acceptable since these are developer tools, not runtime dependencies.
- **No infrastructure changes**: Gallery, identity, and RBAC modules are untouched.
