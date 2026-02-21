## Why

The image build downloads installers (Node.js, Python, PowerShell 7, Git, Azure CLI) via `Invoke-WebRequest` with no integrity verification. A compromised upstream or MITM attack could inject malicious binaries into production images. Additionally, the `openspec_version` variable defaults to `latest`, making builds non-reproducible.

## What Changes

- **Pin OpenSpec version**: Change `openspec_version` default from `latest` to a specific version in `variables.tf` and `terraform.tfvars`
- **Add SHA256 checksum verification**: After each installer download in `main.tf` Phase 1 and Phase 2, verify the file hash against a known-good SHA256 digest stored in Terraform variables
- **Add integrity comment blocks**: Document the expected checksums inline for auditability
- **VS Code and GitHub Desktop are excluded**: These use "latest" floating URLs by design and are not pinned

## Capabilities

### New Capabilities
- `installer-integrity-verification`: SHA256 hash verification for all version-pinned installer downloads (Node.js MSI, Python EXE, PowerShell 7 MSI, Git EXE, Azure CLI MSI)

### Modified Capabilities
- `openspec-version-pinning`: OpenSpec version pinned to immutable release instead of `latest`

## Impact

- **Terraform variables**: New `*_sha256` variables for each installer; `openspec_version` default changes
- **Image builder**: Additional `Get-FileHash` check after each `Get-InstallerWithRetry` call
- **Build time**: Negligible — hash computation is near-instant
- **Maintenance**: SHA256 values must be updated when bumping software versions
