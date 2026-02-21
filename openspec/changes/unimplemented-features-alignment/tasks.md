## 1. Implement Skills Hydration

- [ ] 1.1 Add skills staging in ConfigureAgents customizer: create `C:\ProgramData\OpenClaw\skills` directory and populate with default skill templates
- [ ] 1.2 Add skills copy block to hydration script: copy `C:\ProgramData\OpenClaw\skills\*` to `$env:USERPROFILE\.agents\skills` on first login
- [ ] 1.3 Add `skills_config` variable (list of skill names/sources) or hardcode initial curated set

## 2. Implement MCP Server Configuration

- [ ] 2.1 Add MCP config template creation in ConfigureAgents customizer: write a template `mcp-servers.json` to `C:\ProgramData\OpenClaw\`
- [ ] 2.2 Add MCP config hydration to Active Setup script: copy MCP config to user profile on first login
- [ ] 2.3 Add `mcp_servers` variable (map of server configs) to `terraform/variables.tf`

## 3. Descope Multi-Region in README

- [ ] 3.1 Update README line ~127 to describe current single-region behavior
- [ ] 3.2 Remove or rewrite `target_regions` variable example (line ~2059) as a "future enhancement" callout
- [ ] 3.3 Add note in DR section that multi-region replication requires manual `az sig image-version` commands until implemented
