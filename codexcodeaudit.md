# W365Claw Code Audit (Repository-Wide)

Date: 2026-02-17  
Scope: Terraform (`terraform/`), scripts (`scripts/`), configuration, and documentation (`*.md`, `openspec/` references where relevant)

## Executive Summary
- Hardcoded secrets: **none found** in tracked files.
- Major strengths: modular Terraform layout, least-privilege Azure RBAC model, `terraform.tfvars` ignored, lifecycle protection on gallery resources.
- Main risk areas: supply-chain integrity controls, state/security posture, operational workflow contradiction, and documentation drift.

## Findings

### Critical

1. **Unverified software supply chain during image build**  
Severity: **Critical**  
Category: Security / Operational  
Evidence:
- `terraform/modules/image-builder/main.tf:39` (`Invoke-WebRequest` downloads installers with no checksum/signature verification)
- `terraform/modules/image-builder/main.tf:129` (same pattern repeated)
- `terraform/modules/image-builder/main.tf:236` (`npm install -g openclaw@...`)
- `terraform/modules/image-builder/main.tf:246` (`npm install -g @anthropic-ai/claude-code@...`)
- `terraform/modules/image-builder/main.tf:256` (`npm install -g @fission-ai/openspec@...`)
- `terraform/modules/image-builder/main.tf:266` (`npm install -g @openai/codex@...`)
- `terraform/variables.tf:187` (`openspec_version` defaults to `latest`)
- `terraform/terraform.tfvars:40` (`openspec_version = "latest"`)
Impact:
- A compromised upstream package/release can be silently baked into production images.
- Builds are not fully reproducible or attestable.
Recommendation:
- Pin all packages (including OpenSpec) to immutable versions.
- Add SHA256 verification (or vendor-signed artifact validation) before install.
- Prefer an internal approved artifact mirror/repository and block direct internet fetches in production builds.

### High

1. **Teardown workflow is internally contradictory and can fail at destroy time**  
Severity: **High**  
Category: Operational Gap / Terraform lifecycle design  
Evidence:
- `terraform/modules/gallery/main.tf:8` (`prevent_destroy = true` on gallery)
- `terraform/modules/gallery/main.tf:59` (`prevent_destroy = true` on image definition)
- `README.md:76` (instructs `terraform destroy`)
- `terraform/outputs.tf:48` (instructs `terraform destroy`)
Impact:
- Documented teardown flow conflicts with lifecycle constraints and can block full destroy from the same state.
- Operators may get stuck with partially managed resources and unclear recovery path.
Recommendation:
- Split persistent gallery resources into a separate Terraform state/workspace, or remove broad `terraform destroy` guidance and replace with targeted teardown commands/state boundaries.

2. **Local Terraform backend with no remote state locking/encryption/governance**  
Severity: **High**  
Category: Security / Terraform best practices  
Evidence:
- `terraform/versions.tf:20` (`backend "local" {}`)
Impact:
- No centralized locking, weak collaboration safety, and no centralized access control/auditability for state.
- Increased risk of state drift, accidental overwrite, and data leakage from local machines.
Recommendation:
- Move to remote backend (Azure Storage + state locking pattern) with encryption at rest, least-privilege access, and backup/versioning controls.

3. **Permissive Claude Code enterprise policy defaults to allow mode**  
Severity: **High**  
Category: Security  
Evidence:
- `terraform/modules/image-builder/main.tf:332` (`defaultMode = "allow"`)
Impact:
- Agent/tool execution policy is effectively permissive by default for all provisioned users.
Recommendation:
- Change default policy to a restrictive mode (review/deny-by-default) and explicitly allow only required tool surfaces.

### Medium

1. **ExecutionPolicy bypass in Active Setup launcher**  
Severity: **Medium**  
Category: Security  
Evidence:
- `terraform/modules/image-builder/main.tf:389` (`powershell.exe -ExecutionPolicy Bypass ...`)
Impact:
- Weakens script execution controls and increases abuse potential of startup hydration path.
Recommendation:
- Sign the hydration script and execute under `AllSigned`/policy-compliant mode where possible.

2. **No explicit monitoring/diagnostic settings for build resources**  
Severity: **Medium**  
Category: Operational Gap  
Evidence:
- `terraform/main.tf:1` (resource orchestration contains no `azurerm_monitor_diagnostic_setting` resources)
- `terraform/modules/image-builder/main.tf:462` (AIB template defined without linked diagnostics/log export config)
Impact:
- Limited proactive observability and alerting for build failures/security events.
Recommendation:
- Add diagnostic settings for relevant resources to Log Analytics / SIEM, with alert rules for failed builds and anomalous activity.

3. **Rollback strategy is incomplete in runbook/docs**  
Severity: **Medium**  
Category: Operational Gap / Documentation  
Evidence:
- `README.md:86` (promotion guidance only)
- `README.md:123` (apply→verify→destroy flow only)
- `terraform/outputs.tf:67` (promotion step only)
Impact:
- No clear, tested rollback procedure for bad promoted images (for example, demotion/repointing policy to previous known-good version with command sequence and decision criteria).
Recommendation:
- Add a concrete rollback runbook with explicit commands, ownership, verification gates, and recovery SLA.

4. **Installer commands in workstation bootstrap hide output and skip exit-code checks**  
Severity: **Medium**  
Category: Operational Gap / Script error handling  
Evidence:
- `scripts/Initialize-BuildWorkstation.ps1:313` (`winget ... | Out-Null`)
- `scripts/Initialize-BuildWorkstation.ps1:341` (`winget ... | Out-Null`)
- `scripts/Initialize-BuildWorkstation.ps1:355` (`winget ... | Out-Null`)
Impact:
- Installation failures can be hard to diagnose; script may proceed with stale assumptions.
Recommendation:
- Capture stdout/stderr to log files, validate `$LASTEXITCODE` after each external install command, and fail with actionable error context.

5. **Subscription selector lacks input validation and can terminate script unexpectedly**  
Severity: **Medium**  
Category: Script reliability  
Evidence:
- `scripts/Initialize-BuildWorkstation.ps1:398` (`$subs[[int]$selection]` without bounds/type validation)
Impact:
- Invalid operator input can throw and abort prerequisite setup.
Recommendation:
- Validate numeric range and handle parse failures with retry prompts.

6. **Inconsistent reproducibility stance: some key tools are intentionally latest**  
Severity: **Medium**  
Category: Terraform best practices / Documentation consistency  
Evidence:
- `terraform/modules/image-builder/main.tf:136` (VS Code `.../latest/...`)
- `terraform/modules/image-builder/main.tf:163` (GitHub Desktop `.../latest/...`)
- `terraform/variables.tf:187` (`openspec_version` default `latest`)
Impact:
- Rebuilds can produce materially different images from same Terraform code.
Recommendation:
- Pin all installable components or explicitly classify allowed floating dependencies with risk acceptance and change-control workflow.

### Low

1. **Documentation references a missing companion file (broken links)**  
Severity: **Low**  
Category: Documentation Gap  
Evidence:
- `TerraformApplicationSpecification.md:3` (`./BuildingOpenClawforWindows365UsingAzureComputeGallery.md` missing)
- `TerraformApplicationSpecification.md:1300` (same missing reference)
Impact:
- Readers cannot access stated design rationale source.
Recommendation:
- Add the missing file or update links to an existing canonical document.

2. **Major documentation drift vs current codebase**  
Severity: **Low**  
Category: Documentation Gap / Code quality  
Evidence:
- `TerraformApplicationSpecification.md:90` (shows `random` provider that is no longer in Terraform code)
- `TerraformApplicationSpecification.md:465` (shows `timestamp()` approach, while code uses `time_static`)
- `TerraformApplicationSpecification.md:39` (claims spot instances; no matching Terraform implementation)
Impact:
- Misleads maintainers and increases change risk.
Recommendation:
- Regenerate the specification directly from current Terraform sources or reduce it to architecture-level guidance with references to live code.

3. **Identity resource naming is hardcoded and not environment-parameterized**  
Severity: **Low**  
Category: Code Quality / Reusability  
Evidence:
- `terraform/modules/identity/main.tf:8` (`name = "id-aib-w365-dev"`)
Impact:
- Limits multi-environment reuse and may cause naming conflicts in shared subscriptions.
Recommendation:
- Parameterize identity name (for example include environment/project suffix).

4. **Script policy convention conflict across docs**  
Severity: **Low**  
Category: Documentation Gap  
Evidence:
- `CLAUDE.md:18` (“No Azure CLI (`az`)” convention)
- `scripts/Initialize-BuildWorkstation.ps1:153` and `scripts/Initialize-BuildWorkstation.ps1:163` (Azure CLI actively used)
Impact:
- Confusing guidance for contributors/automation agents.
Recommendation:
- Update `CLAUDE.md` to align with current auth/provider-registration implementation.

## Additional Notes

- **No hardcoded credentials/secrets detected** in repository files scanned.
- Azure RBAC in Terraform is generally least-privilege oriented (`terraform/modules/identity/main.tf:19`, `terraform/modules/identity/main.tf:27`, `terraform/modules/identity/main.tf:35`, `terraform/modules/identity/main.tf:43`).
- `terraform` CLI is not installed in this execution environment, so `terraform fmt -check` and `terraform validate` could not be executed here.

## Priority Remediation Order
1. Implement artifact/package integrity controls and remove floating versions from build path.
2. Resolve state/teardown architecture mismatch (separate state or revise lifecycle/workflow).
3. Move off local backend to remote secured state with locking.
4. Harden runtime policy defaults (`defaultMode`) and remove ExecutionPolicy bypass where feasible.
5. Add monitoring/diagnostic and rollback runbook depth.
6. Clean documentation drift and broken links.
