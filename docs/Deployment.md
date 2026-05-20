# Deployment Guide

## Prerequisites

```powershell
# 1. Install tools
winget install HashiCorp.Terraform
winget install Amazon.AWSCLI
winget install Git.Git

# 2. Verify
terraform --version  # must be >= 1.7.0
aws --version        # must be >= 2.0.0
git --version
```

## Step 1 — AWS Account Setup

You need:
- A dev AWS account
- A prod AWS account
- An IAM user in each with `AdministratorAccess` (for initial bootstrap only)
- A Route53 hosted zone in one of the accounts (typically prod)

```powershell
# Configure profiles
aws configure --profile dev
aws configure --profile prod

# Verify
aws sts get-caller-identity --profile dev
aws sts get-caller-identity --profile prod
```

## Step 2 — Route53 Hosted Zone

If you don't have one:

```powershell
# Create hosted zone
aws route53 create-hosted-zone \
  --name example.com \
  --caller-reference "$(Get-Date -Format 'yyyyMMddHHmmss')" \
  --profile prod

# Note the NS records and update them at your domain registrar
```

## Step 3 — Bootstrap Remote State

Run once per AWS account:

```powershell
# Dev account
cd bootstrap
terraform init

terraform apply `
  -var="environment=dev" `
  -var="aws_profile=dev" `
  -var="github_org=YOUR_GITHUB_ORG" `
  -var="github_repo=aws-website-hosting"

# Note the outputs — you need them for backend.tf files and GitHub secrets
terraform output

# Prod account
terraform apply `
  -var="environment=prod" `
  -var="aws_profile=prod" `
  -var="github_org=YOUR_GITHUB_ORG" `
  -var="github_repo=aws-website-hosting"

terraform output
```

## Step 4 — Update Backend Configs

Replace placeholder values in each `backend.tf` with bootstrap outputs:

```powershell
# Example: environments/dev/solution-a/backend.tf
# Replace: aws-website-hosting-tfstate-dev-XXXXXXXXXXXX
# With:    output "state_bucket_name" from bootstrap (e.g. aws-website-hosting-tfstate-dev-123456789012)
```

## Step 5 — Update tfvars

Edit each `terraform.tfvars` file:

```powershell
# environments/dev/solution-a/terraform.tfvars
domain_name      = "dev.yourdomain.com"
hosted_zone_name = "yourdomain.com"

# environments/prod/solution-a/terraform.tfvars
domain_name      = "yourdomain.com"
hosted_zone_name = "yourdomain.com"

# environments/dev/solution-b/terraform.tfvars
domain_name          = "ec2-dev.yourdomain.com"
content_s3_bucket    = "your-content-bucket-name"
```

## Step 6 — GitHub Secrets Setup

In your GitHub repository: **Settings → Secrets and variables → Actions**

Add these secrets:

| Secret Name | Value |
|-------------|-------|
| `AWS_ROLE_ARN_DEV` | ARN from bootstrap output `github_actions_role_arn` (dev account) |
| `AWS_ROLE_ARN_PROD` | ARN from bootstrap output `github_actions_role_arn` (prod account) |
| `CONTENT_BUCKET_DEV` | S3 bucket name for EC2 content (dev) |
| `CONTENT_BUCKET_PROD` | S3 bucket name for EC2 content (prod) |

## Step 7 — GitHub Environment Protection

Create two GitHub Environments: **Settings → Environments**

1. `dev` — no restrictions
2. `prod` — add required reviewer (yourself)

This creates the manual approval gate for production deployments.

## Step 8 — Deploy Solution A (dev)

```powershell
cd environments/dev/solution-a

# Initialize
terraform init

# Plan
terraform plan -out=tfplan

# Review the plan, then apply
terraform apply tfplan

# Verify outputs
terraform output
```

Expected outputs:
```
bucket_id                   = "aws-website-hosting-website-dev-123456789012"
distribution_id             = "EXXXXXXXXXXXXX"
distribution_domain_name    = "dxxxxxxxxx.cloudfront.net"
```

## Step 9 — Upload Website Content

```powershell
# Sync local website files to S3
aws s3 sync website/solution-a/ `
  s3://$(terraform -chdir=environments/dev/solution-a output -raw bucket_id)/ `
  --profile dev

# Invalidate CloudFront cache
$DIST_ID = terraform -chdir=environments/dev/solution-a output -raw distribution_id
aws cloudfront create-invalidation `
  --distribution-id $DIST_ID `
  --paths "/*" `
  --profile dev
```

## Step 10 — Deploy Solution B (dev)

```powershell
cd environments/dev/solution-b

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

## Step 11 — Verify Deployments

```powershell
# Solution A — check HTTPS
curl -I https://dev.yourdomain.com

# Solution B — check HTTPS
curl -I https://ec2-dev.yourdomain.com

# Check certificate
# Windows
$web = Invoke-WebRequest -Uri "https://dev.yourdomain.com" -UseBasicParsing
$web.StatusCode  # should be 200
```

## Step 12 — Push to GitHub (triggers CI/CD)

```powershell
git add .
git commit -m "feat: initial infrastructure deployment"
git push origin develop
# → GitHub Actions: deploys to dev

git checkout main
git merge develop
git push origin main
# → GitHub Actions: requests approval, then deploys to prod
```

---

## Rollback Procedures

### Solution A (S3 + CloudFront)

```powershell
# Rollback website content — restore previous S3 version
$BUCKET = terraform -chdir=environments/prod/solution-a output -raw bucket_id

# List versions of a specific file
aws s3api list-object-versions --bucket $BUCKET --prefix "index.html"

# Restore a previous version
aws s3api copy-object `
  --bucket $BUCKET `
  --copy-source "$BUCKET/index.html?versionId=PREVIOUS_VERSION_ID" `
  --key "index.html"

# Invalidate cache
aws cloudfront create-invalidation `
  --distribution-id $(terraform output -raw distribution_id) `
  --paths "/*"
```

### Terraform State Rollback

```powershell
# Terraform state is versioned in S3
# List state versions
aws s3api list-object-versions `
  --bucket aws-website-hosting-tfstate-prod-XXXXXXXXXXXX `
  --prefix "prod/solution-a/terraform.tfstate"

# To roll back: restore previous state version
# Then run terraform apply to reconcile infrastructure
```

---

## DNS Propagation

ACM certificate DNS validation can take **5–30 minutes**. Route53 ALIAS records propagate in **< 60 seconds** within AWS but may take **up to 48 hours** for external DNS TTL expiry.

```powershell
# Check DNS propagation
nslookup dev.yourdomain.com
nslookup dev.yourdomain.com 8.8.8.8

# Check certificate status
aws acm describe-certificate `
  --certificate-arn "arn:aws:acm:us-east-1:XXXX:certificate/YYYY" `
  --query 'Certificate.Status'
```

---

## Complete Command Reference

```powershell
# Format all Terraform files
terraform fmt -recursive

# Validate all environments
Get-ChildItem -Path environments -Recurse -Filter "*.tf" | `
  Select-Object -ExpandProperty DirectoryName | `
  Sort-Object -Unique | `
  ForEach-Object { Push-Location $_; terraform validate; Pop-Location }

# Plan with variable file
terraform plan -var-file="terraform.tfvars" -out=tfplan

# Apply saved plan
terraform apply tfplan

# Destroy (with confirmation prompt)
terraform destroy

# Destroy without prompt (CAREFUL)
terraform destroy -auto-approve

# Show current state
terraform show

# List resources in state
terraform state list

# Import existing resource
terraform import aws_s3_bucket.example my-bucket-name

# Unlock state (if stuck)
terraform force-unlock LOCK_ID
```
