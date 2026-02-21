## Why

Three features are documented in the README but have no implementation in Terraform. These represent aspirational documentation that got ahead of the code. We need to either implement or descope them.

## What Changes

### 1. Curated Skills Hydration (implement)
- **README** (lines 1362, 1454, 3679, 3690): Describes pre-seeding agent skills from `C:\ProgramData\OpenClaw\skills` to `$env:USERPROFILE\.agents\skills` during first-login hydration
- **Code**: Hydration script only copies OpenClaw config — no skills logic
- **Resolution:** Add skills copy block to the hydration script in `terraform/modules/image-builder/main.tf` and add a skills staging step in the ConfigureAgents customizer to populate `C:\ProgramData\OpenClaw\skills`

### 2. MCP Server Configuration (implement)
- **README** (lines 1388, 1403, 1462, 3680, 3691): Describes MCP server config creation and hydration
- **Code**: No MCP references in image-builder module
- **Resolution:** Add MCP config template creation in ConfigureAgents customizer and hydration of MCP config in the Active Setup script

### 3. Multi-Region Replication (descope from README)
- **README** (line 127, 2059): Documents `target_regions` variable with `regional_replica_count`
- **Code** (`image-builder/main.tf:471`): Only replicates to `[var.location]`
- **Resolution:** Update README to document current single-region behavior and note multi-region as a future enhancement. Multi-region adds operational complexity that isn't needed for the book's scope.

## Impact

- **Code changes** for items 1 and 2 (hydration script + customizer additions)
- **README changes** for item 3 (descope multi-region to future work)
