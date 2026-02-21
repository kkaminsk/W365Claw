# Supply Chain Integrity: W365Claw Image Build

**Date:** 2026-02-17
**Status:** Implemented
**Audit Finding:** Critical — Codex Code Audit (codexcodeaudit.md, Finding #1)
**OpenSpec:** `openspec/changes/supply-chain-integrity/`

---

## Problem

The W365Claw image build process downloads software installers and npm packages from the public internet during Azure VM Image Builder execution. Prior to this remediation:

- **No checksum verification** — Downloaded MSI/EXE installers were executed without verifying SHA256 hashes against known-good values
- **Floating version pins** — `openspec_version` defaulted to `"latest"`, making builds non-reproducible
- **No integrity gate** — A compromised upstream release (supply chain attack) would be silently baked into every provisioned Windows 365 developer image

This is a critical risk because the built images are deployed to production Cloud PCs used by the development team.

## What Changed

### 1. SHA256 Checksum Verification for Binary Installers

A new `Test-InstallerHash` function was added to the Phase 1 (Core Runtimes) customizer script in `terraform/modules/image-builder/main.tf`:

```powershell
function Test-InstallerHash {
    param([string]$FilePath, [string]$ExpectedHash)
    if ([string]::IsNullOrWhiteSpace($ExpectedHash)) {
        Write-Host "[INTEGRITY] No SHA256 provided for $(Split-Path $FilePath -Leaf) — skipping verification"
        return
    }
    $actual = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
    if ($actual -ne $ExpectedHash.ToUpper()) {
        Write-Error "[INTEGRITY] SHA256 MISMATCH for $(Split-Path $FilePath -Leaf)! Expected: $ExpectedHash Got: $actual"
        exit 1
    }
    Write-Host "[INTEGRITY] SHA256 verified for $(Split-Path $FilePath -Leaf)"
}
```

**Behavior:**
- If a SHA256 hash is provided → verifies before installation, **fails the build** on mismatch
- If no hash is provided (empty string) → logs a warning and continues (opt-in enforcement)
- This allows gradual adoption: populate hashes as you pin versions, without breaking existing builds

### 2. Terraform Variables for Checksums

Five new variables added to `terraform/variables.tf`:

| Variable | Description | Default |
|----------|-------------|---------|
| `node_sha256` | SHA256 for Node.js MSI installer | `""` (opt-in) |
| `python_sha256` | SHA256 for Python installer | `""` (opt-in) |
| `pwsh_sha256` | SHA256 for PowerShell 7 MSI installer | `""` (opt-in) |
| `git_sha256` | SHA256 for Git for Windows installer | `""` (opt-in) |
| `azure_cli_sha256` | SHA256 for Azure CLI MSI installer | `""` (opt-in) |

These are passed through the module chain: `terraform/main.tf` → `terraform/modules/image-builder/variables.tf` → inline script interpolation.

### 3. OpenSpec Version Pinned

| Before | After |
|--------|-------|
| `openspec_version = "latest"` | `openspec_version = "0.9.1"` |

This was the only npm package using a floating version. All other packages (OpenClaw, Claude Code, Codex CLI) were already pinned.

### 4. Intentional Exceptions

Two tools are **intentionally excluded** from SHA256 verification:

| Tool | URL Pattern | Reason |
|------|-------------|--------|
| **VS Code** | `https://update.code.visualstudio.com/latest/win32-x64-system/stable` | Microsoft auto-update redirector; no stable versioned URL with published checksums |
| **GitHub Desktop** | `https://central.github.com/deployments/desktop/desktop/latest/GitHubDesktopSetup-x64.msi` | GitHub's CDN always serves latest; no versioned download with checksums |

Both are signed binaries from Microsoft/GitHub. The risk is accepted because:
- They are user-facing GUI tools, not security-critical infrastructure
- Pinning them would require maintaining a mirror or custom download logic
- Their auto-update mechanisms will supersede the installed version on first login anyway

## How to Populate Checksums

When bumping a software version, obtain the SHA256 from the official release:

### Node.js
```
https://nodejs.org/dist/v24.13.1/SHASUMS256.txt
```
Find the line for `node-v24.13.1-x64.msi`.

### Python
```
https://www.python.org/downloads/release/python-3143/
```
Click "Files" → find `python-3.14.3-amd64.exe` → copy the SHA256.

### PowerShell 7
```
https://github.com/PowerShell/PowerShell/releases/tag/v7.4.13
```
Check the `hashes.sha256` asset or compute from the downloaded MSI.

### Git for Windows
```
https://github.com/git-for-windows/git/releases/tag/v2.53.0.windows.1
```
SHA256 listed in release notes or compute from the downloaded EXE.

### Azure CLI
```
https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows
```
Microsoft publishes checksums for MSI releases.

### Example terraform.tfvars
```hcl
node_sha256      = "abc123..."
python_sha256    = "def456..."
pwsh_sha256      = "789ghi..."
git_sha256       = "jkl012..."
azure_cli_sha256 = "mno345..."
```

## npm Package Integrity

npm packages are verified through a different mechanism:

1. **Version pinning** — All packages pinned to exact versions (no `latest`, `^`, or `~`)
2. **npm audit gate** — `npm audit --global --audit-level=high` runs after installation and **fails the build** if high/critical vulnerabilities are found
3. **SBOM generation** — A Software Bill of Materials is written to `C:\ProgramData\ImageBuild\sbom-npm-global.json` during every build

npm's built-in integrity checking (via `package-lock.json` SHA512 hashes) does not apply to global installs. The version pin + audit gate is the primary control.

## Verification

After a build, the SBOM at `C:\ProgramData\ImageBuild\sbom-software-manifest.json` records all installed versions:

```json
{
  "buildDate": "2026-02-17T...",
  "nodeVersion": "v24.13.1",
  "pythonVersion": "Python 3.14.3",
  "gitVersion": "git version 2.53.0.windows.1",
  "pwshVersion": "PowerShell 7.4.13",
  "azCliVersion": "azure-cli 2.83.0",
  "openclawVersion": "2026.2.14",
  "claudeVersion": "2.1.42",
  "openspecVersion": "0.9.1",
  "codexVersion": "codex-cli 0.101.0"
}
```

## Files Modified

| File | Change |
|------|--------|
| `terraform/variables.tf` | Added 5 `*_sha256` variables; pinned `openspec_version` to `0.9.1` |
| `terraform/main.tf` | Pass SHA256 variables to image-builder module |
| `terraform/modules/image-builder/variables.tf` | Accept SHA256 variables |
| `terraform/modules/image-builder/main.tf` | Added `Test-InstallerHash` function; call after each download |
| `terraform/terraform.tfvars` | Pinned `openspec_version = "0.9.1"` |

## Future Improvements

1. **Mandatory checksums** — Once all SHA256 values are populated, change `Test-InstallerHash` to fail on empty hash (remove the skip path)
2. **Internal artifact mirror** — Host approved installers in an Azure Storage account with SAS tokens, eliminating direct internet fetches during builds
3. **Cosign/Sigstore verification** — For npm packages, verify provenance attestations once the ecosystem supports it broadly
4. **SLSA compliance** — Move toward SLSA Level 2+ by adding build provenance metadata and reproducible build verification
