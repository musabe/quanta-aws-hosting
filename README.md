# quanta-aws-hosting

[![Terraform](https://img.shields.io/badge/Terraform-1.7+-7B42BC?logo=terraform)](https://terraform.io)
[![AWS](https://img.shields.io/badge/AWS-Multi--Account-FF9900?logo=amazonaws)](https://aws.amazon.com)
[![CI](https://github.com/musabe/quanta-aws-hosting/actions/workflows/terraform-ci.yml/badge.svg)](https://github.com/musabe/quanta-aws-hosting/actions)

Production-grade AWS website hosting — two architectures, two accounts, automated CI/CD.

## Environments

| Environment | Account | Domain | Profile |
|-------------|---------|--------|---------|
| **prod** | `390951754623` | `quantaweb.dev` | `quanta-web-prod` |
| **dev** | `858371255598` | `quantadev.dev` | `quanta-web-dev` |

## Solutions

| Solution | Architecture | Dev URL | Prod URL |
|----------|-------------|---------|----------|
| **A** | S3 + CloudFront + ACM + Route53 | `https://quantadev.dev` | `https://quantaweb.dev` |
| **B** | EC2 + Nginx + ALB + ACM + Route53 | `https://ec2.quantadev.dev` | `https://ec2.quantaweb.dev` |

## Quick Start

### 1 — Bootstrap (run once per account)

```powershell
# Dev account
.\scripts\bootstrap.ps1 -Environment dev

# Prod account
.\scripts\bootstrap.ps1 -Environment prod
```

### 2 — Add GitHub Secrets

Go to **GitHub → Settings → Secrets → Actions** and add:

| Secret | Value (from bootstrap output) |
|--------|-------------------------------|
| `AWS_ROLE_ARN_DEV` | ARN from dev bootstrap |
| `AWS_ROLE_ARN_PROD` | ARN from prod bootstrap |

### 3 — Deploy Solution A (dev)

```powershell
cd environments/dev/solution-a
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 4 — Deploy Solution B (dev)

```powershell
cd environments/dev/solution-b
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

## Repository Structure

```
quanta-aws-hosting/
├── .github/workflows/
│   ├── terraform-ci.yml          # PR validation
│   ├── deploy-solution-a.yml     # S3+CloudFront deploy
│   └── deploy-solution-b.yml     # EC2+Nginx deploy
├── bootstrap/                    # Run once per account
├── modules/
│   ├── s3-cloudfront/
│   ├── ec2-nginx/
│   ├── acm/
│   ├── route53/
│   └── vpc/
├── environments/
│   ├── dev/
│   │   ├── solution-a/           # quantadev.dev
│   │   └── solution-b/           # ec2.quantadev.dev
│   └── prod/
│       ├── solution-a/           # quantaweb.dev
│       └── solution-b/           # ec2.quantaweb.dev
├── website/
│   ├── solution-a/               # Static site content
│   └── solution-b/               # Nginx site content
└── scripts/
    ├── bootstrap.ps1
    └── deploy.ps1
```

## CI/CD Flow

```
feature/* → PR → develop   →  deploy to dev  (automatic)
develop   → PR → main      →  deploy to prod (manual approval)
```

## Docs

- [Architecture](docs/Architecture.md)
- [Deployment](docs/Deployment.md)
- [Security](docs/Security.md)
- [Troubleshooting](docs/Troubleshooting.md)
