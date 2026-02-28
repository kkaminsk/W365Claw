## Why

The book README (`W365ClawBook/README.md`) has three configuration mismatches against the actual Terraform code that will confuse readers and cause incorrect expectations.

## What Changes

### 1. Build VM Size Default (README says D2, code says D4)
- **README** (lines 254, 292, 294): Claims `Standard_D2s_v5` is the default
- **Code** (`terraform/variables.tf:89`): Default is `Standard_D4s_v5`
- **Resolution:** Update README to reflect `Standard_D4s_v5` as the default. The code was intentionally upgraded for faster builds.

### 2. Source Image Version (README says 25H2/26200, code says 24H2/26100)
- **README** (lines 815, 823): States `26200.7840.260206` and Windows 11 25H2
- **Code** (`terraform/variables.tf:121,127`): Defaults are `win11-24h2-ent` / `26100.2894.250113`
- **Resolution:** Update README to match code defaults. The image definition name already says 25H2 which is the *target* naming convention, but the source marketplace image is 24H2 until 25H2 is GA in marketplace.

### 3. Hydration Overwrite Behavior (README says preserve, code overwrites)
- **README** (line 1448): Shows `if (-not (Test-Path $configFile))` guard
- **Code** (`terraform/modules/image-builder/main.tf:406`): Does `Copy-Item ... -Force` unconditionally
- **Resolution:** Update code to add the preserve guard, matching the README's documented behavior. Preserving user customizations is the correct enterprise pattern.

## Impact

- **README changes** for items 1 and 2
- **Code change** for item 3 (add config-exists guard to hydration script)
