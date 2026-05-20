# Troubleshooting

## Common Issues

---

### ACM Certificate Stuck in PENDING_VALIDATION

**Symptom:** `terraform apply` hangs for > 5 minutes at `aws_acm_certificate_validation.this`

**Cause:** DNS validation records haven't been created or Route53 hasn't propagated.

**Fix:**
```powershell
# Check whether validation records were created
aws route53 list-resource-record-sets `
  --hosted-zone-id YOUR_ZONE_ID `
  --query "ResourceRecordSets[?Type=='CNAME']"

# Check certificate status
aws acm describe-certificate `
  --certificate-arn YOUR_CERT_ARN `
  --region us-east-1 `
  --query 'Certificate.{Status:Status,ValidationOptions:DomainValidationOptions}'
```

If validation records exist but status is still PENDING, wait — ACM can take up to 30 minutes. If records are missing, the Route53 zone ID may be wrong.

---

### CloudFront Returns 403 Forbidden

**Symptom:** Site URL returns 403 after infrastructure deployment.

**Causes and fixes:**

1. **S3 content not uploaded yet**
   ```powershell
   aws s3 ls s3://YOUR_BUCKET/ --profile dev
   # If empty, run the sync:
   aws s3 sync website/solution-a/ s3://YOUR_BUCKET/ --profile dev
   ```

2. **OAC bucket policy not applied**
   ```powershell
   aws s3api get-bucket-policy --bucket YOUR_BUCKET
   # Should show AllowCloudFrontOAC statement
   ```

3. **CloudFront distribution still deploying**
   ```powershell
   aws cloudfront get-distribution --id YOUR_DIST_ID `
     --query 'Distribution.Status'
   # Wait until Status is "Deployed" (not "InProgress")
   ```

---

### CloudFront Returns Stale Content After S3 Update

**Symptom:** Updated files uploaded to S3 but old content still served.

**Fix:**
```powershell
# Create invalidation
aws cloudfront create-invalidation `
  --distribution-id YOUR_DIST_ID `
  --paths "/*"

# Wait for completion
aws cloudfront wait invalidation-completed `
  --distribution-id YOUR_DIST_ID `
  --id INVALIDATION_ID
```

**Prevention:** CI/CD workflow always creates invalidation after sync.

---

### Terraform State Lock Error

**Symptom:**
```
Error acquiring the state lock
Lock Info:
  ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  ...
```

**Cause:** A previous Terraform operation was interrupted while holding the lock.

**Fix:**
```powershell
# Only do this if you are CERTAIN no other operation is running
terraform force-unlock LOCK_ID
```

---

### GitHub Actions OIDC Authentication Failure

**Symptom:** `Error: Could not assume role with ARN...`

**Checks:**

1. Verify the GitHub OIDC provider exists in the AWS account:
   ```powershell
   aws iam list-open-id-connect-providers --profile dev
   ```

2. Verify the trust policy allows your repo:
   ```powershell
   aws iam get-role --role-name aws-website-hosting-github-actions-dev `
     --query 'Role.AssumeRolePolicyDocument'
   ```
   The `sub` condition must match `repo:YOUR_ORG/YOUR_REPO:*`

3. Verify the workflow has `id-token: write` permission:
   ```yaml
   permissions:
     id-token: write
     contents: read
   ```

---

### EC2 Instance Unreachable via ALB (502 Bad Gateway)

**Symptom:** ALB returns 502.

**Checks:**

1. **Health check failing**
   ```powershell
   aws elbv2 describe-target-health `
     --target-group-arn YOUR_TG_ARN
   # Look at TargetHealth.State and Description
   ```

2. **Nginx not started** — check SSM:
   ```powershell
   aws ssm start-session --target YOUR_INSTANCE_ID
   # Inside session:
   sudo systemctl status nginx
   sudo journalctl -u nginx -n 50
   ```

3. **Security group mismatch** — EC2 SG must allow inbound from ALB SG, not a CIDR

4. **User data failed** — check cloud-init log:
   ```bash
   cat /var/log/user-data.log
   cat /var/log/cloud-init-output.log
   ```

---

### Route53 DNS Not Resolving

**Symptom:** `nslookup dev.example.com` returns NXDOMAIN.

**Checks:**
```powershell
# Verify record was created
aws route53 list-resource-record-sets `
  --hosted-zone-id YOUR_ZONE_ID `
  --query "ResourceRecordSets[?Name=='dev.example.com.']"

# Check NS records match your registrar
aws route53 get-hosted-zone --id YOUR_ZONE_ID `
  --query 'DelegationSet.NameServers'
```

If NS records at your registrar don't match the Route53 delegation set, DNS will never resolve.

---

### `terraform init` Backend Error

**Symptom:** `Error: Failed to get existing workspaces: S3 bucket does not exist`

**Cause:** You haven't run bootstrap, or you have the wrong bucket name in `backend.tf`.

**Fix:**
1. Run bootstrap: `cd bootstrap && terraform apply`
2. Copy the `state_bucket_name` output
3. Update `backend.tf` with the correct bucket name
4. Re-run `terraform init`

---

### `terraform fmt -check` Fails in CI

**Symptom:** CI fails with formatting errors.

**Fix locally:**
```powershell
# Auto-fix all formatting
terraform fmt -recursive

git add -A
git commit -m "style: terraform fmt"
git push
```

---

## Useful Debug Commands

```powershell
# Check CloudFront distribution details
aws cloudfront get-distribution --id DIST_ID

# Test HTTPS from command line
curl -v https://dev.example.com 2>&1 | Select-String -Pattern "SSL|TLS|HTTP|connected"

# Check S3 bucket policy
aws s3api get-bucket-policy --bucket BUCKET_NAME | ConvertFrom-Json

# List all Route53 records in zone
aws route53 list-resource-record-sets --hosted-zone-id ZONE_ID

# Check EC2 instance state
aws ec2 describe-instances --instance-ids i-xxxx `
  --query 'Reservations[0].Instances[0].{State:State.Name,PublicIP:PublicIpAddress,PrivateIP:PrivateIpAddress}'

# Check ALB target health
aws elbv2 describe-target-health --target-group-arn TG_ARN

# View SSM session history
aws ssm describe-sessions --state History

# Check Terraform state
terraform state list
terraform state show aws_cloudfront_distribution.website
```
