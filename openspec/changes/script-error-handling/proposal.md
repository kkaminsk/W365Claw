## Why

`Initialize-BuildWorkstation.ps1` pipes winget output to `Out-Null`, hiding installation failures. The subscription selector accepts arbitrary input without validation, which can throw and abort the script.

## What Changes

- **Capture winget output** to a log variable instead of piping to `Out-Null`
- **Validate `$LASTEXITCODE`** after each winget install command
- **Add bounds checking** on subscription selector input (validate numeric range, handle parse failures)

## Capabilities

### Modified Capabilities
- `prerequisite-installation-reliability`: winget failures are now logged and detected
- `subscription-selector-robustness`: Invalid input is caught with a retry prompt

## Impact

- **Single file**: `scripts/Initialize-BuildWorkstation.ps1`
- **No breaking changes**: Existing usage is identical; error handling is additive
