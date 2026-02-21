<#
.SYNOPSIS
    Removes AIB build resources while preserving the gallery and image versions.

.DESCRIPTION
    Targeted teardown for W365Claw. Removes the AIB image template and managed
    identity via Terraform, while leaving the gallery and image definition intact
    (these have prevent_destroy = true).

    This script replaces `terraform destroy` which would fail on protected resources.

.PARAMETER TerraformDir
    Path to the terraform/ directory. Defaults to ..\terraform relative to this script.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Teardown-BuildResources.ps1
    .\Teardown-BuildResources.ps1 -Force
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [string]$TerraformDir = (Join-Path $PSScriptRoot "..\terraform")
)

$ErrorActionPreference = "Stop"

$TerraformDir = (Resolve-Path $TerraformDir -ErrorAction Stop).Path

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  W365Claw — Targeted Build Resource Teardown" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will remove:" -ForegroundColor Yellow
Write-Host "  • AIB image template (azapi_resource.image_template)" -ForegroundColor Yellow
Write-Host "  • Build action (azapi_resource_action.run_build)" -ForegroundColor Yellow
Write-Host "  • Build timestamp (time_static.build_time)" -ForegroundColor Yellow
Write-Host ""
Write-Host "This will PRESERVE:" -ForegroundColor Green
Write-Host "  • Azure Compute Gallery" -ForegroundColor Green
Write-Host "  • Image definition" -ForegroundColor Green
Write-Host "  • All image versions" -ForegroundColor Green
Write-Host "  • Resource group" -ForegroundColor Green
Write-Host "  • Managed identity + RBAC" -ForegroundColor Green
Write-Host ""

if (-not $Force) {
    $response = Read-Host "Continue? [Y/n]"
    if ($response -ne "" -and $response -ne "Y" -and $response -ne "y") {
        Write-Host "Aborted." -ForegroundColor Red
        exit 0
    }
}

Push-Location $TerraformDir
try {
    # Destroy only the image-builder module resources
    Write-Host "Destroying AIB template resources..." -ForegroundColor Yellow
    terraform destroy `
        -target="module.image_builder" `
        -var-file="terraform.tfvars" `
        -auto-approve

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Terraform targeted destroy failed (exit code $LASTEXITCODE)"
        exit 1
    }

    Write-Host ""
    Write-Host "✅ Build resources removed. Gallery and images preserved." -ForegroundColor Green
    Write-Host ""
} finally {
    Pop-Location
}
