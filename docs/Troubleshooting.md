# Troubleshooting

This document contains common operational failure scenarios, root causes, and debugging workflows for the quanta-aws-hosting infrastructure. It is intended as a first-response reference during incidents or deployment issues.

---

## 🔐 ACM / TLS

### Certificate Stuck in PENDING_VALIDATION

**Symptom:** `terraform apply` hangs at `aws_acm_certificate_validation.this` for more than 5 minutes.

**Common root causes:**
- DNS validation records not yet created in Route53
- Wrong hosted zone ID in Terraform configuration
- Nameservers not propagated to the domain registrar

**Diagnosis:**

```powershell
# Check whether validation CNAME records exist
aws route53 list-resource-record-sets `
  --hosted-zone-id YOUR_ZONE_ID `
  --query "ResourceRecordSets[?Type=='CNAME']"

# Check certificate validation status
aws acm describe-certificate `
  --certificate-arn YOUR_CERT_ARN `
  --region us-east-1 `
  --query 'Certificate.{Status:Status,ValidationOptions:DomainValidationOptions}'
```

If validation records exist but status remains `PENDING_VALIDATION`, wait — ACM validation can take up to 30 minutes after DNS propagation.

> [!NOTE]
> ACM certificates for CloudFront must exist in `us-east-1` regardless of deployment region.

---

## 🌐 CloudFront

### 403 Forbidden After Deployment

**Symptom:** Site returns 403 immediately after infrastructure deployment.

**Common root causes:**

1. **S3 bucket is empty** — content not yet uploaded

   ```powershell
   aws s3 ls s3://YOUR_BUCKET/ --profile quanta-web-prod
   # If empty, sync content:
   aws s3 sync website/solution-a/ s3://YOUR_BUCKET/ --profile quanta-web-prod
   ```

2. **OAC bucket policy not applied**

   ```powershell
   aws s3api get-bucket-policy --bucket YOUR_BUCKET
   # Should contain AllowCloudFrontOAC statement with distribution ARN
   ```

3. **Distribution still deploying**

   ```powershell
   aws cloudfront get-distribution --id YOUR_DIST_ID `
     --query 'Distribution.Status'
   # Wait until Status is "Deployed"
   ```

### Stale Content After S3 Update

**Symptom:** Updated files uploaded to S3 but old content still served from CloudFront.

```powershell
# Create cache invalidation
aws cloudfront create-invalidation `
  --distribution-id YOUR_DIST_ID `
  --paths "/*"

# Wait for invalidation to complete
aws cloudfront wait invalidation-completed `
  --distribution-id YOUR_DIST_ID `
  --id INVALIDATION_ID
```

The CI/CD pipeline creates a cache invalidation automatically after every content sync.

---

## 🖥️ EC2 / ALB

### 502 Bad Gateway

**Symptom:** ALB returns 502 after deployment.

**Common root causes:**
- EC2 bootstrap still in progress
- Nginx installation failed in `user_data`
- Security group misconfiguration

**Diagnosis — check target health:**

```powershell
aws elbv2 describe-target-health `
  --target-group-arn YOUR_TG_ARN `
  --query 'TargetHealthDescriptions[0].TargetHealth'
```

**Diagnosis — check bootstrap log via SSM:**

```powershell
aws ssm start-session --target YOUR_INSTANCE_ID --profile quanta-web-prod
```

Inside the session:

```bash
sudo tail -100 /var/log/user-data.log
sudo systemctl status nginx
```

**Diagnosis — check security groups:**

EC2 security group must allow inbound from the ALB security group ID — not a CIDR range. Security group references follow ALB IP changes automatically; CIDR-based rules do not.

### Health Check Failures

**Symptom:** Target group shows `Target.FailedHealthChecks`.

The ALB health check hits `GET /health` on port 80. Nginx must be running and the `/health` location must return HTTP 200.

```bash
# Verify Nginx config includes health endpoint
sudo nginx -t
sudo cat /etc/nginx/conf.d/quanta.conf

# Test health endpoint locally on the instance
curl http://localhost/health
```

---

## ☁️ Route53

### DNS Not Resolving

**Symptom:** `nslookup quantadev.dev` returns NXDOMAIN.

```powershell
# Verify the A record was created
aws route53 list-resource-record-sets `
  --hosted-zone-id YOUR_ZONE_ID `
  --query "ResourceRecordSets[?Name=='quantadev.dev.']"

# Verify NS records match your registrar
aws route53 get-hosted-zone --id YOUR_ZONE_ID `
  --query 'DelegationSet.NameServers'
```

If NS records at the domain registrar do not match the Route53 delegation set, DNS will never resolve regardless of record configuration.

---

## 🔄 Terraform

### State Lock Error

**Symptom:**

```
Error acquiring the state lock
Lock Info:
  ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

**Cause:** A previous Terraform operation was interrupted while holding the DynamoDB lock.

> [!WARNING]
> `terraform force-unlock` should only be used after confirming no active Terraform operations exist. Forcing an unlock while an apply is running can corrupt state.

```powershell
terraform force-unlock LOCK_ID
```

### Backend Initialisation Failure

**Symptom:** `Error: Failed to get existing workspaces: S3 bucket does not exist`

**Cause:** Bootstrap has not been run, or `backend.tf` contains an incorrect bucket name.

1. Run `cd bootstrap && terraform apply` to create the state bucket
2. Copy the `state_bucket_name` output
3. Update `backend.tf` with the correct bucket name
4. Re-run `terraform init`

### Format Check Fails in CI

```powershell
# Fix formatting locally before pushing
terraform fmt -recursive

git add -A
git commit -m "style: terraform fmt"
git push
```

---

## 🚀 GitHub Actions

### OIDC Authentication Failure

**Symptom:** `Error: Could not assume role with ARN...`

**Checks:**

Verify the OIDC provider exists in the target AWS account:

```powershell
aws iam list-open-id-connect-providers --profile quanta-web-prod
```

Verify the trust policy `sub` condition matches the repository:

```powershell
aws iam get-role `
  --role-name quanta-aws-hosting-github-actions-prod `
  --query 'Role.AssumeRolePolicyDocument'
```

The `sub` condition must be `repo:musabe/quanta-aws-hosting:*`.

Verify the workflow declares `id-token: write` permission:

```yaml
permissions:
  id-token: write
  contents: read
```

### GitHub Actions Deployment Drift

Manual infrastructure changes made outside Terraform may cause plan drift — Terraform will detect unexpected resource modifications on the next run.

To identify drift:

```powershell
cd environments/prod/solution-a
terraform plan
```

Review the plan output carefully. Resources shown as modified (`~`) or replaced (`-/+`) should be investigated before applying. Prefer resolving drift through Terraform rather than further manual changes.

---

## 🛠️ Useful Debug Commands

```powershell
# CloudFront distribution status
aws cloudfront get-distribution --id DIST_ID --query 'Distribution.Status'

# S3 bucket policy
aws s3api get-bucket-policy --bucket BUCKET_NAME | ConvertFrom-Json

# All Route53 records in a zone
aws route53 list-resource-record-sets --hosted-zone-id ZONE_ID

# EC2 instance state
aws ec2 describe-instances --instance-ids i-EXAMPLE `
  --query 'Reservations[0].Instances[0].{State:State.Name,PrivateIP:PrivateIpAddress}'

# ALB target health
aws elbv2 describe-target-health --target-group-arn TG_ARN

# SSM session history (audit trail)
aws ssm describe-sessions --state History

# Terraform state inspection
terraform state list
terraform state show module.s3_cloudfront.aws_cloudfront_distribution.website
```

---

## 📋 Operational Best Practices

- Avoid manual infrastructure changes outside Terraform — drift causes plan noise and operational risk
- Rely on `terraform plan` reviews in CI before every merge to protected branches
- Prefer SSM Session Manager over any direct instance access pattern
- Validate DNS propagation and ACM certificate status before troubleshooting application-layer issues
- Review ALB access logs and CloudFront access logs before assuming infrastructure faults
