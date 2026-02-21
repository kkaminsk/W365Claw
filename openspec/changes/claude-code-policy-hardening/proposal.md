## Why

The Claude Code enterprise managed settings deploy with `defaultMode = "allow"`, which grants permissive tool/agent execution for all provisioned users by default. This is an unnecessary security risk.

## What Changes

- Change `defaultMode` from `"allow"` to `"allowWithPermission"` in the Claude Code managed settings in `terraform/modules/image-builder/main.tf`

## Capabilities

### Modified Capabilities
- `claude-code-policy`: Default permission mode changed from allow to allowWithPermission — users are prompted before tool execution

## Impact

- **Single line change** in `terraform/modules/image-builder/main.tf`
- **User experience**: Claude Code will prompt users before executing tools, rather than auto-allowing
