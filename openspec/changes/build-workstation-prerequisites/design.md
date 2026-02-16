## Approach

Single PowerShell script with three phases: **check → install → verify**. The script is idempotent — running it on an already-configured machine is a no-op. It works in both Windows PowerShell 5.1 and PowerShell 7+.

## Script Architecture

```
Initialize-BuildWorkstation.ps1
├── Phase 1: Pre-Flight Checks (non-destructive)
│   ├── OS validation (Windows 10/11 x64)
│   ├── Administrator check
│   ├── Tool detection (Terraform, Azure CLI, Git, Az module)
│   ├── Azure auth check (az account show)
│   ├── Resource provider status (4 providers)
│   └── terraform init status (.terraform/ exists)
│
├── Phase 2: Installation (interactive, with confirmation)
│   ├── Missing tools → winget install (fallback: direct download)
│   ├── Missing Az module → Install-Module
│   ├── No Azure login → launch az login
│   ├── Unregistered RPs → Register-AzResourceProvider + wait
│   └── No .terraform/ → terraform init
│
└── Phase 3: Post-Installation Verification
    ├── Re-run all checks
    ├── Summary table (✅/❌ per item)
    └── Exit code 0 (all pass) or 1 (failures remain)
```

## Key Decisions

### winget as primary installer
- Available on Windows 10 1709+ and all Windows 11
- No external dependency (unlike Chocolatey)
- Fallback: direct ZIP/MSI download for Terraform if winget is unavailable

### Azure CLI for Terraform auth (not Az module)
- Terraform's AzureRM provider uses the Azure CLI credential chain by default
- Az PowerShell module is for post-build operations only (Get-AzGalleryImageVersion, etc.)
- Both are installed, but for different purposes

### No -Force flag by default
- Script prompts before each installation
- Pass `-Force` parameter to skip prompts (for automated/scripted use)

### Version checking
- Uses semantic version comparison, not string matching
- Minimum versions: Terraform >= 1.5.0, Azure CLI >= 2.60, Git >= 2.40, Az module >= 12.0

### Resource provider registration
- Checks all four providers: `Microsoft.Compute`, `Microsoft.VirtualMachineImages`, `Microsoft.Network`, `Microsoft.ManagedIdentity`
- Only registers those not already in "Registered" state
- Polls every 10 seconds until registered (timeout: 5 minutes per provider)

## What This Does NOT Do

- Install or configure VS Code, Node.js, or any developer tools (those go in the image, not the build workstation)
- Set up CI/CD service principals
- Modify Terraform code or variables
- Configure VPN or network access
