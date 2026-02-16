## Context

Platform Engineering needs to produce reproducible Windows 365 developer images containing OpenClaw and Claude Code. The current manual process is error-prone and unversioned. This design covers the Terraform-based automation using Azure Compute Gallery and Azure VM Image Builder.

The solution targets a single resource group, single region, manual `terraform apply` workflow with immediate teardown after build.

## Goals / Non-Goals

**Goals:**
- Fully automated, reproducible image builds from a single `terraform apply`
- Windows 365 ACG compliance (all five mandatory feature flags)
- Least-privilege identity model — no broad Contributor roles
- Pinned software versions for supply chain integrity
- Cost minimisation via teardown-after-build pattern
- Per-user config hydration without baking secrets into the image

**Non-Goals:**
- CI/CD pipeline (manual invocation only)
- Intune policy management
- Monitoring/alerting infrastructure
- Multi-region replication (single region only)
- ANTHROPIC_API_KEY management (user responsibility)

## Decisions

### 1. Modular Terraform structure (root + 3 modules)
**Decision:** Three child modules — `gallery`, `identity`, `image-builder` — orchestrated by a root module.
**Rationale:** Separation of concerns. Gallery and identity are reusable across image definitions. Image-builder contains the most complex logic (customizers) and benefits from isolation.
**Alternative considered:** Flat single-module layout — rejected for maintainability at scale.

### 2. azapi provider for AIB template
**Decision:** Use `azapi_resource` for `Microsoft.VirtualMachineImages/imageTemplates` instead of `azurerm`.
**Rationale:** The `azurerm` provider lacks full coverage for AIB customizers, distribution targets, and VM profile configuration. `azapi` provides direct ARM API access and is the recommended approach for AIB.
**Alternative considered:** `azurerm_virtual_machine_image_template` — rejected due to incomplete feature support.

### 3. Inline PowerShell scripts (no storage account)
**Decision:** All customizer scripts are inline in the Terraform HCL, not stored in a blob storage account.
**Rationale:** Eliminates the need for a storage account, SAS tokens, and network access rules. Scripts are version-controlled alongside the Terraform config. Simplifies the security model.
**Alternative considered:** External scripts in Azure Blob Storage — rejected for added complexity and cost with no meaningful benefit for this use case.

### 4. Phased installation with restarts
**Decision:** Four installation phases with Windows restarts between runtime installation and tool installation.
**Rationale:** Some installers (Node.js MSI, Python) modify system PATH. A restart ensures the updated PATH is available to subsequent phases. AIB's `WindowsRestart` customizer handles this cleanly.

### 5. Active Setup for per-user config hydration
**Decision:** Use Windows Active Setup to deploy OpenClaw configuration on first user login rather than baking user-specific config into the image.
**Rationale:** Active Setup runs once per user per version, making it ideal for initial configuration. Avoids baking API keys or user-specific settings into a shared image. The version field enables re-hydration on image updates.

### 6. Local backend (no remote state)
**Decision:** Use Terraform's local backend — state file lives on the operator's machine.
**Rationale:** The infrastructure is ephemeral (destroyed after each build). Only the gallery image version persists. Remote state adds complexity with no benefit for a teardown-after-build workflow.

### 7. Pinned versions everywhere
**Decision:** Pin source image version, all software installer versions, npm package versions, and Terraform provider versions.
**Rationale:** Build reproducibility. Using "latest" for any component creates non-deterministic builds that are impossible to audit or reproduce.

## Risks / Trade-offs

- **[Risk] Inline script size limits** → AIB has a ~256KB limit per customizer. Current scripts are well under this. Monitor if scripts grow significantly.
- **[Risk] Download failures during build** → Mitigated by `Get-InstallerWithRetry` with 3 attempts and 10-second backoff. GitHub/Node.js CDN outages could still cause failures.
- **[Risk] npm audit false positives** → Build fails on high/critical vulnerabilities. Could block builds for issues in transitive dependencies outside our control. → Mitigation: Update pinned versions or temporarily adjust audit level.
- **[Risk] PowerShell 7 URL hardcoded** → The download URL includes a specific version (`7.4.7`) but isn't parameterised. → Should be extracted to a variable in future iteration.
- **[Risk] Local state loss** → If the operator's machine crashes during a build, state is lost and resources may need manual cleanup. → Acceptable for ephemeral infrastructure pattern.
- **[Trade-off] No remote state** → Simplicity over collaboration. Only one operator runs builds at a time.
- **[Trade-off] Single region** → Lower cost and complexity, but no geo-redundancy for the image. Acceptable for dev workloads.

## Migration Plan

1. `terraform init` — initialise local backend and download providers
2. `terraform plan -var-file=terraform.tfvars` — review changes
3. `terraform apply` — deploys gallery, identity, AIB template, triggers build (~60-90 min)
4. Verify image version in gallery
5. `terraform destroy` — remove all build infrastructure (image version persists)
6. Import image into Windows 365 via Intune portal
7. Assign to provisioning policy

**Rollback:** Previous image versions remain in the gallery. Revert provisioning policy to previous version. No Terraform rollback needed.

## Open Questions

- Should PowerShell 7 version be parameterised like other software versions?
- Should we add a `terraform output` that generates the `Get-AzGalleryImageVersion` command for easy verification?
- Future: Should config hydration use Intune PowerShell scripts instead of Active Setup for better compliance reporting?
