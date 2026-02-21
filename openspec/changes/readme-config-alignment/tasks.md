## 1. Fix Build VM Size in README

- [ ] 1.1 Update Mermaid diagram reference from `Standard_D2s_v5` to `Standard_D4s_v5` (line ~254)
- [ ] 1.2 Update Layer 2 narrative from `Standard_D2s_v5` to `Standard_D4s_v5` (line ~292)
- [ ] 1.3 Update cost note to reflect D4 as default, D2 as cost-saving downgrade option (line ~294)

## 2. Fix Source Image Version in README

- [ ] 2.1 Update variable table: `source_image_version` default from `26200.7840.260206` to `26100.2894.250113` (line ~815)
- [ ] 2.2 Update inline code example showing `26200.7840.260206` to `26100.2894.250113` (line ~823)
- [ ] 2.3 Add note explaining 24H2 source image vs 25H2 image definition naming convention

## 3. Fix Hydration Overwrite Guard in Code

- [ ] 3.1 Add `if (-not (Test-Path $configFile))` guard around `Copy-Item` in `terraform/modules/image-builder/main.tf` hydration script
