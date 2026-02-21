## MODIFIED Requirements

### Requirement: Deterministic build timestamp (H1)
The system SHALL use a `time_static` resource instead of `timestamp()` to compute the image version's end-of-life date, ensuring the value is captured once in state and does not change on subsequent plan/apply cycles.

#### Problem
`modules/image-builder/main.tf` uses `timeadd(timestamp(), "2160h")` in the `end_of_life_date` local. Because `timestamp()` is evaluated at plan time, every `terraform plan` produces a diff on the AIB template — even when nothing else changed. This causes unintended resource recreation and potential build disruption.

#### Fix
Add a `time_static` resource and reference it in the local:

**File:** `modules/image-builder/main.tf`

```hcl
# BEFORE
locals {
  end_of_life_date = timeadd(timestamp(), "2160h")
}

# AFTER
resource "time_static" "build_time" {}

locals {
  end_of_life_date = timeadd(time_static.build_time.rfc3339, "2160h")
}
```

The `time` provider is already declared in `versions.tf`. The `time_static` resource stores its value in state and only changes when explicitly tainted or recreated.

#### Scenario: No perpetual diff on plan
- **WHEN** `terraform plan` is run without any configuration changes
- **THEN** no diff SHALL appear for the `end_of_life_date` field on the image template

---

### Requirement: Reliable PowerShell 7 download URL (H2)
The system SHALL use a version-pinned download URL for PowerShell 7 that does not depend on the `/latest/` redirect.

#### Problem
`modules/image-builder/main.tf` Phase 1 customizer contains:
```
https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.7-win-x64.msi
```
The `/latest/` path redirects to the most recent release, but the filename `PowerShell-7.4.7-win-x64.msi` is version-specific. When a newer version is released, this URL will 404.

#### Fix
Pin to the exact release URL:

**File:** `modules/image-builder/main.tf` (Phase 1 customizer inline script)

```hcl
# BEFORE
$pwshUrl = "https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.7-win-x64.msi"

# AFTER
$pwshUrl = "https://github.com/PowerShell/PowerShell/releases/download/v7.4.7/PowerShell-7.4.7-win-x64.msi"
```

Optionally, extract into a variable for consistency with other pinned versions:

**File:** `modules/image-builder/variables.tf`
```hcl
variable "pwsh_version" {
  description = "PowerShell 7 version to install"
  type        = string
  default     = "7.4.7"
}
```

**File:** Phase 1 customizer
```hcl
$pwshUrl = "https://github.com/PowerShell/PowerShell/releases/download/v${var.pwsh_version}/PowerShell-${var.pwsh_version}-win-x64.msi"
```

#### Scenario: Build succeeds regardless of latest PowerShell release
- **WHEN** a newer PowerShell 7 version is released on GitHub
- **THEN** the image build SHALL still download and install the pinned version without 404 errors
