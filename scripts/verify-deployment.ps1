# scripts/verify-deployment.ps1
# Post-deployment verification checks.
# Run after terraform apply to confirm everything is working.

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("dev","prod")]
    [string]$Environment,

    [Parameter(Mandatory=$true)]
    [ValidateSet("solution-a","solution-b","both")]
    [string]$Solution = "both"
)

$ErrorActionPreference = "Continue"
$allPassed = $true

function Test-Endpoint {
    param([string]$Url, [string]$Label)
    
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 15
        if ($response.StatusCode -eq 200) {
            Write-Host "  ✅ $Label — HTTP $($response.StatusCode)" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  ⚠️  $Label — HTTP $($response.StatusCode)" -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host "  ❌ $Label — FAILED: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

Write-Host "=== Deployment Verification: $Environment ===" -ForegroundColor Cyan

# ─────────────────────────────────────────────
# Solution A checks
# ─────────────────────────────────────────────
if ($Solution -in "solution-a","both") {
    Write-Host "`nSolution A (S3 + CloudFront):" -ForegroundColor Yellow
    
    Push-Location "environments/$Environment/solution-a"
    
    $bucketId    = terraform output -raw bucket_id 2>$null
    $distId      = terraform output -raw distribution_id 2>$null
    $distDomain  = terraform output -raw distribution_domain_name 2>$null
    
    Pop-Location
    
    # Check S3 bucket exists
    try {
        aws s3api head-bucket --bucket $bucketId --profile $Environment 2>$null
        Write-Host "  ✅ S3 Bucket exists: $bucketId" -ForegroundColor Green
    } catch {
        Write-Host "  ❌ S3 Bucket not found: $bucketId" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Check CloudFront distribution status
    $distStatus = aws cloudfront get-distribution --id $distId `
        --query 'Distribution.Status' --output text 2>$null
    if ($distStatus -eq "Deployed") {
        Write-Host "  ✅ CloudFront status: Deployed" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  CloudFront status: $distStatus (may still be deploying)" -ForegroundColor Yellow
    }
    
    # Test HTTPS endpoint
    if ($distDomain) {
        $passed = Test-Endpoint -Url "https://$distDomain" -Label "CloudFront domain"
        if (-not $passed) { $allPassed = $false }
    }
}

# ─────────────────────────────────────────────
# Solution B checks
# ─────────────────────────────────────────────
if ($Solution -in "solution-b","both") {
    Write-Host "`nSolution B (EC2 + Nginx):" -ForegroundColor Yellow
    
    Push-Location "environments/$Environment/solution-b"
    
    $instanceId = terraform output -raw instance_id 2>$null
    $albDns     = terraform output -raw alb_dns_name 2>$null
    
    Pop-Location
    
    # Check EC2 instance state
    $instanceState = aws ec2 describe-instances `
        --instance-ids $instanceId `
        --query 'Reservations[0].Instances[0].State.Name' `
        --output text `
        --profile $Environment 2>$null
    
    if ($instanceState -eq "running") {
        Write-Host "  ✅ EC2 instance running: $instanceId" -ForegroundColor Green
    } else {
        Write-Host "  ❌ EC2 instance state: $instanceState" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Test ALB endpoint
    if ($albDns) {
        $passed = Test-Endpoint -Url "http://$albDns" -Label "ALB health"
        if (-not $passed) { $allPassed = $false }
    }
}

Write-Host ""
if ($allPassed) {
    Write-Host "✅ All checks passed" -ForegroundColor Green
} else {
    Write-Host "❌ Some checks failed — review output above" -ForegroundColor Red
    Write-Host "See docs/Troubleshooting.md for fixes"
}
