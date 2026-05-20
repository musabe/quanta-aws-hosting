# scripts/deploy.ps1
# Manual deployment helper — wraps Terraform commands with validation.
# Use this for local deployments or when bypassing CI/CD.
# CI/CD (GitHub Actions) is the preferred deployment path.

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("dev","prod")]
    [string]$Environment,

    [Parameter(Mandatory=$true)]
    [ValidateSet("solution-a","solution-b","both")]
    [string]$Solution,

    [Parameter(Mandatory=$false)]
    [ValidateSet("plan","apply","destroy")]
    [string]$Action = "plan",

    [switch]$AutoApprove
)

$ErrorActionPreference = "Stop"

# Safety check for production
if ($Environment -eq "prod" -and $Action -eq "apply" -and -not $AutoApprove) {
    Write-Host "⚠️  WARNING: You are about to deploy to PRODUCTION" -ForegroundColor Red
    $confirm = Read-Host "Type 'yes' to confirm"
    if ($confirm -ne "yes") {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 0
    }
}

function Invoke-TerraformDeploy {
    param(
        [string]$WorkingDir,
        [string]$Env,
        [string]$SolutionName
    )

    Write-Host "`n=== $SolutionName ($Env) ===" -ForegroundColor Cyan
    Push-Location $WorkingDir

    try {
        # Init
        Write-Host "→ terraform init" -ForegroundColor Gray
        terraform init -reconfigure
        if ($LASTEXITCODE -ne 0) { throw "init failed" }

        # Format check
        Write-Host "→ terraform fmt -check" -ForegroundColor Gray
        terraform fmt -check
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Run 'terraform fmt -recursive' to fix formatting" -ForegroundColor Yellow
            throw "fmt check failed"
        }

        # Validate
        Write-Host "→ terraform validate" -ForegroundColor Gray
        terraform validate
        if ($LASTEXITCODE -ne 0) { throw "validate failed" }

        if ($Action -eq "plan" -or $Action -eq "apply") {
            Write-Host "→ terraform plan" -ForegroundColor Gray
            terraform plan -out=tfplan -no-color
            if ($LASTEXITCODE -ne 0) { throw "plan failed" }
        }

        if ($Action -eq "apply") {
            $applyArgs = @("apply", "tfplan")
            if ($AutoApprove) { $applyArgs += "-auto-approve" }
            Write-Host "→ terraform apply" -ForegroundColor Gray
            & terraform @applyArgs
            if ($LASTEXITCODE -ne 0) { throw "apply failed" }

            Write-Host "`nOutputs:" -ForegroundColor Green
            terraform output
        }

        if ($Action -eq "destroy") {
            Write-Host "→ terraform destroy" -ForegroundColor Red
            $destroyArgs = @("destroy")
            if ($AutoApprove) { $destroyArgs += "-auto-approve" }
            & terraform @destroyArgs
            if ($LASTEXITCODE -ne 0) { throw "destroy failed" }
        }

        Write-Host "✅ $SolutionName ($Env) — $Action complete" -ForegroundColor Green
    }
    finally {
        # Clean up plan file
        if (Test-Path "tfplan") { Remove-Item "tfplan" -Force }
        Pop-Location
    }
}

$solutions = if ($Solution -eq "both") { @("solution-a","solution-b") } else { @($Solution) }

foreach ($sol in $solutions) {
    $dir = "environments/$Environment/$sol"
    if (-not (Test-Path $dir)) {
        Write-Error "Directory not found: $dir"
    }
    Invoke-TerraformDeploy -WorkingDir $dir -Env $Environment -SolutionName $sol
}

Write-Host "`n✅ All done" -ForegroundColor Green
