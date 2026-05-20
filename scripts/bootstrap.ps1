# scripts/bootstrap.ps1
# Run this ONCE per account before any Terraform.
# Usage:
#   .\scripts\bootstrap.ps1 -Environment dev
#   .\scripts\bootstrap.ps1 -Environment prod

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("dev","prod")]
    [string]$Environment
)

$ErrorActionPreference = "Stop"

$ProfileMap = @{
    "dev"  = "quanta-web-dev"
    "prod" = "quanta-web-prod"
}
$AccountMap = @{
    "dev"  = "858371255598"
    "prod" = "390951754623"
}

$Profile    = $ProfileMap[$Environment]
$AccountId  = $AccountMap[$Environment]

Write-Host "=== Quanta AWS Hosting Bootstrap ===" -ForegroundColor Cyan
Write-Host "Environment : $Environment" -ForegroundColor Yellow
Write-Host "Profile     : $Profile"
Write-Host "Account     : $AccountId"

# Verify credentials
Write-Host "`nVerifying AWS credentials..." -ForegroundColor Cyan
$Identity = aws sts get-caller-identity --profile $Profile --output json | ConvertFrom-Json
Write-Host "✅ Authenticated as: $($Identity.Arn)"

# Run Terraform bootstrap
Write-Host "`nRunning bootstrap Terraform..." -ForegroundColor Cyan
Push-Location bootstrap

terraform init
terraform apply `
    -var="environment=$Environment" `
    -var="aws_profile=$Profile" `
    -auto-approve

$StateBucket   = terraform output -raw state_bucket_name
$DynamoTable   = terraform output -raw dynamodb_table_name
$GitHubRoleArn = terraform output -raw github_actions_role_arn

Pop-Location

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "BOOTSTRAP COMPLETE — $Environment" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Add this GitHub Secret:" -ForegroundColor Yellow
Write-Host "  Name  : AWS_ROLE_ARN_$($Environment.ToUpper())"
Write-Host "  Value : $GitHubRoleArn"
Write-Host ""
Write-Host "State bucket : $StateBucket" -ForegroundColor Gray
Write-Host "Lock table   : $DynamoTable" -ForegroundColor Gray
