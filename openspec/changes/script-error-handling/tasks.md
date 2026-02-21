## 1. Capture Winget Output

- [x] 1.1 Replace `winget ... | Out-Null` with output capture and logging for Terraform install
- [x] 1.2 Replace `winget ... | Out-Null` with output capture and logging for Azure CLI install
- [x] 1.3 Replace `winget ... | Out-Null` with output capture and logging for Git install
- [x] 1.4 Add `$LASTEXITCODE` validation after each winget command

## 2. Subscription Selector Bounds Checking

- [x] 2.1 Wrap subscription selector in try/catch with numeric range validation and retry
