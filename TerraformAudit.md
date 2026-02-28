# Terraform Audit Report: W365Claw Developer Image

**Date:** 2026-02-15  
**Auditor:** BHG-Bot (automated engineering review)  
**Scope:** `C:\Temp\GitHub\W365Claw\terraform\`

---

## Summary

The Terraform solution is well-structured, follows modular best practices, and implements a solid least-privilege identity model. Several issues were identified ranging from low to high severity. Overall the solution is **production-ready with minor remediation**.

| Severity | Count |
|----------|-------|
| 🔴 High | 2 |
| 🟡 Medium | 5 |
| 🟢 Low | 4 |

---

## 🔴 High Severity

### H1: `timestamp()` in locals causes perpetual diff — ✅ Remediated

**Status:** ✅ Remediated — uses `time_static` resource now  
**File:** `modules/image-builder/main.tf` (line: `end_of_life_date`)  
**Issue:** `timeadd(timestamp(), "2160h")` is evaluated on every `plan`/`apply`, meaning `end_of_life_date` changes every run. This forces a replacement of the AIB template on every apply, even when nothing else changed.  
**Impact:** Unintended resource recreation; potential build disruption.  
**Recommendation:** Use a `time_static` resource (from the `time` provider, already declared) to capture build time once:
```hcl
resource "time_static" "build_time" {}

locals {
  end_of_life_date = timeadd(time_static.build_time.rfc3339, "2160h")
}
```
This stores the timestamp in state and only changes when the resource is tainted/recreated.

### H2: PowerShell 7 download URL is hardcoded and uses `/latest/` — ✅ Remediated

**Status:** ✅ Remediated — uses pinned `/download/v$PwshVersion/` URL  
**File:** `modules/image-builder/main.tf` (Phase 1 customizer)  
**Issue:** The URL `https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.7-win-x64.msi` contradicts itself — it uses `/latest/` in the path but specifies version `7.4.7` in the filename. If PowerShell releases a newer version, the `/latest/` redirect will 404 for the `7.4.7` filename.  
**Impact:** Build failure when PowerShell 7.4.7 is no longer the latest release.  
**Recommendation:** Either:
- Pin to a specific release URL: `https://github.com/PowerShell/PowerShell/releases/download/v7.4.7/PowerShell-7.4.7-win-x64.msi`
- Or parameterise as `var.pwsh_version` like the other software versions.

---

## 🟡 Medium Severity

### M1: No `.gitignore` for sensitive files — ✅ Remediated

**Status:** ✅ Remediated — `.gitignore` exists at `terraform/.gitignore`  
**Issue:** `terraform.tfvars` contains `subscription_id` and should not be committed. No `.gitignore` exists.  
**Recommendation:** Add a `.gitignore`:
```
*.tfstate
*.tfstate.backup
.terraform/
terraform.tfvars
```

### M2: RBAC role assignments lack `skip_service_principal_aad_check` — ✅ Remediated

**Status:** ✅ Remediated — all 4 role assignments have `skip_service_principal_aad_check = true`  
**File:** `modules/identity/main.tf`  
**Issue:** When creating a managed identity and assigning roles in the same apply, the AAD principal may not have propagated yet, causing intermittent failures.  
**Recommendation:** Add `skip_service_principal_aad_check = true` to each `azurerm_role_assignment`, or add a `time_sleep` resource between identity creation and role assignment.

### M3: No `lifecycle` block to prevent accidental gallery deletion — ✅ Remediated

**Status:** ✅ Remediated — both gallery resources have `lifecycle { prevent_destroy = true }`  
**File:** `modules/gallery/main.tf`  
**Issue:** `terraform destroy` will delete the gallery and all image versions. The spec says to destroy after build, but the gallery should persist.  
**Recommendation:** Add `lifecycle { prevent_destroy = true }` to the gallery and image definition resources, or separate the gallery into its own state/workspace.

### M4: VS Code installer not version-pinned — ⚠️ Accepted

**Status:** ⚠️ Accepted — intentionally uses latest for evergreen updates  
**File:** `modules/image-builder/main.tf` (Phase 2)  
**Issue:** VS Code downloads from `/latest/` — not pinned. Every build may get a different VS Code version, breaking reproducibility.  
**Recommendation:** Pin VS Code to a specific version URL or document this as an accepted exception.

### M5: GitHub Desktop uses `/latest/` MSI — ⚠️ Accepted

**Status:** ⚠️ Accepted — intentionally uses latest for evergreen updates  
**File:** `modules/image-builder/main.tf` (Phase 2)  
**Issue:** Same as M4 — GitHub Desktop is not version-pinned.  
**Recommendation:** Pin or document the exception.

---

## 🟢 Low Severity

### L1: `random` provider declared but unused — ✅ Remediated

**Status:** ✅ Remediated — `random` provider not present in `versions.tf`  
**File:** `versions.tf`  
**Issue:** The `random` provider is declared but never used in any module.  
**Recommendation:** Remove to reduce provider download time, or add a comment explaining future use.

### L2: Helper functions duplicated across phases — ⚠️ Accepted

**Status:** ⚠️ Accepted — limitation of inline AIB scripts (cannot share code across customizer phases)  
**File:** `modules/image-builder/main.tf`  
**Issue:** `Update-SessionEnvironment` and `Get-InstallerWithRetry` are copy-pasted in Phases 1, 2, and 3. Any bug fix must be applied three times.  
**Recommendation:** Accept for now (inline scripts can't share code), but document the duplication. Consider a Phase 0 that dot-sources a shared module.

### L3: `npm audit --global` may not work as expected — ✅ Remediated

**Status:** ✅ Remediated — replaced with package inventory logging (`npm list -g --depth=0`)  
**Issue:** `npm audit` on global packages has limited support and may not detect vulnerabilities in the global install tree reliably.  
**Recommendation:** Test this during a dry-run build. Consider `npm audit` within each package's directory instead.

### L4: No Terraform output for build status/logs — ⚠️ Accepted

**Status:** ⚠️ Accepted — `next_steps` output provides post-build guidance  
**Issue:** After `azapi_resource_action.run_build` completes, there's no output showing where to find build logs.  
**Recommendation:** Add an output with the AIB log location: `https://portal.azure.com > Image Templates > <template> > Logs`

---

## Security Assessment

| Area | Rating | Notes |
|------|--------|-------|
| Identity & RBAC | ✅ Strong | Least-privilege with 4 specific roles; no Contributor/Owner |
| Secret management | ✅ Strong | No API keys in image; user-managed post-login |
| Supply chain | ✅ Good | Pinned npm versions, npm audit gate, SBOM generation |
| Source image | ✅ Good | Pinned marketplace version with validation |
| Script integrity | ✅ Good | Inline scripts, no external storage dependencies |
| State security | ⚠️ Acceptable | Local state only; acceptable for ephemeral teardown pattern |

---

## Windows 365 Compliance

| Requirement | Status |
|-------------|--------|
| Hyper-V Gen 2 | ✅ |
| x64 architecture | ✅ |
| SecurityType: TrustedLaunchSupported | ✅ |
| IsHibernateSupported: True | ✅ |
| DiskControllerTypes: SCSI,NVMe | ✅ |
| IsAcceleratedNetworkSupported: True | ✅ |
| IsSecureBootSupported: True | ✅ |
| Windows 11 Enterprise source | ✅ |
| Not domain-joined | ✅ (marketplace image) |
| Generalised (Sysprep) | ✅ (AIB handles) |

---

## Recommendations Summary

| # | Action | Severity | Effort | Status |
|---|--------|----------|--------|--------|
| H1 | Replace `timestamp()` with `time_static` | High | 5 min | ✅ Remediated |
| H2 | Fix PowerShell 7 download URL | High | 5 min | ✅ Remediated |
| M1 | Add `.gitignore` | Medium | 2 min | ✅ Remediated |
| M2 | Add `skip_service_principal_aad_check` | Medium | 5 min | ✅ Remediated |
| M3 | Add `prevent_destroy` to gallery | Medium | 5 min | ✅ Remediated |
| M4/M5 | Pin VS Code and GitHub Desktop versions | Medium | 15 min | ⚠️ Accepted |
| L1 | Remove unused `random` provider | Low | 1 min | ✅ Remediated |
| L2 | Consolidate helper functions | Low | — | ⚠️ Accepted |
| L3 | Fix `npm audit --global` | Low | 5 min | ✅ Remediated |
| L4 | Add build status output | Low | 10 min | ⚠️ Accepted |

---

## Audit Revision History

| Date | Action |
|------|--------|
| 2026-02-15 | Initial audit |
| 2026-02-28 | Status review: H1, H2, M1, M2, M3, L1, L3 remediated; M4, M5, L2, L4 accepted |
