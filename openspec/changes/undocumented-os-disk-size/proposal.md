## Why

The `os_disk_size_gb` variable exists in `terraform/variables.tf:98` (default: 128 GB) and is passed to the AIB template's VM profile, but it's not mentioned in the README's variable tables or configuration guidance. Operators may not know they can tune this.

## What Changes

- **README**: Add `os_disk_size_gb` to the variable reference table alongside `build_vm_size` and `build_timeout_minutes`
- **README**: Add a note in the build VM section explaining when to increase disk size (e.g., if adding more software or Windows Update cache needs space)

## Impact

- **Documentation only** — no code changes
