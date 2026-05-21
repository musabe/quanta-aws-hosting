# Deployment Guide

This document covers the full deployment lifecycle — prerequisites, bootstrap, environment deployment, CI/CD workflow, rollback procedures, and DNS validation. It is intended as an operational reference for anyone deploying or maintaining this infrastructure.

---

## 🚀 Prerequisites

Install the required tooling on Windows:

```powershell
winget install HashiCorp.Terraform
winget install Amazon.AWSCLI
winget install Git.Git
```

Verify versions:

```powershell
terraform --version   # >= 1.7.0
aws --version         # >= 2.0.0
git --version
```

---

## ☁️ AWS Account Setup

This project requires two AWS accounts — one for dev, one for prod. Using separate accounts provides blast radius containment and independent billing visibility.

Create an IAM admin user in each account for initial bootstrap:

```powershell
# Configure AWS CLI profiles
aws configure --profile quanta-web-dev
aws configure --profile quanta-web-prod

# Verify both profiles
aws sts get-caller-identity --profile quanta-web-dev
aws sts get-caller-identity --profile quanta-web-prod
```

> [!NOTE]
> `AdministratorAccess` is required only for the initial bootstrap step. Ongoing deployments use scoped GitHub Actions OIDC roles created during bootstrap.

---

## 🏗️ Bootstrap Remote State

Bootstrap creates the S3 state bucket, DynamoDB lock table, GitHub OIDC provider, and IAM deployment role in each account. It uses local state and is run once per account by a human operator.

Separate backend state per environment reduces blast radius — a state corruption or accidental destroy in dev cannot affect prod.

```powershell
cd bootstrap

# Bootstrap dev account
terraform init
terraform apply -var="environment=dev" -var="aws_profile=quanta-web-dev" -auto-approve

# Clear local state between accounts
Remove-Item -Force terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item -Force terraform.tfstate.backup -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .terraform -ErrorAction SilentlyContinue

# Bootstrap prod account
terraform init
terraform apply -var="environment=prod" -var="aws_profile=quanta-web-prod" -auto-approve
```

Note the outputs from each run — the `github_actions_role_arn` values are needed for GitHub Secrets.

---

## 🔑 GitHub Secrets and Environments

Add the OIDC role ARNs to GitHub repository secrets:

**Settings → Secrets and variables → Actions → New repository secret**

| Secret | Value |
|--------|-------|
| `AWS_ROLE_ARN_DEV` | `github_actions_role_arn` from dev bootstrap |
| `AWS_ROLE_ARN_PROD` | `github_actions_role_arn` from prod bootstrap |

Create two GitHub Environments (**Settings → Environments**):

- `dev` — no restrictions, deploys automatically on push to `develop`
- `prod` — add yourself as a required reviewer to create a manual approval gate

> [!IMPORTANT]
> GitHub Environment Protection rules create the manual approval gate for production deployments. Without this, a push to `main` deploys immediately.

---

## 🌍 DNS Setup

Register domains in Route53 or create hosted zones for existing domains:

```powershell
# Create hosted zone for dev domain
aws route53 create-hosted-zone `
  --name quantadev.dev `
  --caller-reference "$(Get-Date -Format 'yyyyMMddHHmmss')" `
  --profile quanta-web-dev
```

Note the four NS records returned — update your domain registrar if the domain was registered externally.

> [!NOTE]
> ACM certificate DNS validation can take 5–30 minutes. CloudFront distributions propagate globally over 10–15 minutes. Plan deployments accordingly.

---

## 🔄 Environment Deployment

Deploy Solution A (S3 + CloudFront) to dev:

```powershell
cd environments/dev/solution-a

terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```

Upload website content and invalidate the cache:

```powershell
# Sync website files to S3
aws s3 sync website/solution-a/ `
  s3://$(terraform output -raw bucket_id)/ `
  --profile quanta-web-dev

# Invalidate CloudFront edge caches
aws cloudfront create-invalidation `
  --distribution-id $(terraform output -raw distribution_id) `
  --paths "/*" `
  --profile quanta-web-dev
```

Deploy Solution B (EC2 + Nginx) to dev:

```powershell
cd environments/dev/solution-b

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

The EC2 instance bootstraps automatically via `user_data` — Nginx installs and content syncs from S3 on first boot.

---

## 🔁 CI/CD Pipeline

Pushes to `develop` deploy to dev automatically. Pushes to `main` trigger a manual approval gate before deploying to prod.

```
feature/* → PR → develop   →  deploy to dev   (automatic)
develop   → PR → main      →  deploy to prod  (requires approval)
```

PRs trigger `terraform fmt -check`, `terraform validate`, and `terraform plan`. The plan output is posted as a PR comment for review.

> [!WARNING]
> Always review `terraform plan` output carefully before approving production deployments. Unexpected resource replacements (`-/+`) should be investigated before applying.

---

## 🔙 Rollback Procedures

### Solution A — Content Rollback

S3 versioning enables instant content rollback without redeployment:

```powershell
# List versions of a file
aws s3api list-object-versions `
  --bucket BUCKET_NAME `
  --prefix "index.html"

# Restore a previous version
aws s3api copy-object `
  --bucket BUCKET_NAME `
  --copy-source "BUCKET_NAME/index.html?versionId=PREVIOUS_VERSION_ID" `
  --key "index.html"

# Invalidate cache after restore
aws cloudfront create-invalidation `
  --distribution-id DIST_ID `
  --paths "/*"
```

### Infrastructure Rollback

Terraform state is versioned in S3. To roll back infrastructure:

```powershell
# List state file versions
aws s3api list-object-versions `
  --bucket quanta-aws-hosting-tfstate-prod-111111111111 `
  --prefix "prod/solution-a/terraform.tfstate"

# Restore a previous state version via the S3 console or CLI
# Then run terraform apply to reconcile infrastructure to the restored state
```

> [!WARNING]
> `terraform destroy -auto-approve` should never be used in production without explicit change review.

---

## 🌍 DNS Validation

After deployment, verify DNS resolution:

```powershell
# Check DNS propagation
nslookup quantaweb.dev
nslookup quantaweb.dev 8.8.8.8

# Check ACM certificate status
aws acm describe-certificate `
  --certificate-arn "arn:aws:acm:us-east-1:111111111111:certificate/EXAMPLE" `
  --query 'Certificate.Status'

# Verify HTTPS response
curl -I https://quantaweb.dev
```

---

## 📋 Operational Recommendations

- Prefer CI/CD over manual `terraform apply` in production — pipeline runs are auditable
- Review `terraform plan` output on every PR before merging
- Isolate environments per AWS account to contain blast radius
- Monitor ACM and CloudFront propagation timing after deployments
- Use `terraform state list` and `terraform state show` to inspect state before destructive operations
- Run `terraform fmt -recursive` before committing to avoid CI failures
