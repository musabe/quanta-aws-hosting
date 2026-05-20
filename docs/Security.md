# Security

## Security Design Principles

This project applies **defence in depth** — multiple independent security controls so that a failure in any single layer does not compromise the whole system.

---

## 1. IAM Strategy — Least Privilege

### GitHub Actions OIDC (No Static Credentials)

**Why OIDC over access keys:**
- Access keys are long-lived — if leaked, they remain valid until manually rotated
- OIDC tokens are short-lived (15 minutes) and scoped to a specific repo/branch
- No secret to store, rotate, or accidentally commit

```
GitHub Actions job
    │ Requests OIDC token from GitHub
    ▼
GitHub token.actions.githubusercontent.com
    │ Returns signed JWT with claims:
    │   sub: repo:ORG/REPO:ref:refs/heads/main
    ▼
AWS STS AssumeRoleWithWebIdentity
    │ Validates JWT, checks trust policy conditions
    ▼
Temporary credentials (15min TTL)
```

The IAM role trust policy restricts assumption to:
- Your specific GitHub organisation and repository
- Optionally: specific branch (`refs/heads/main`)

### EC2 Instance Profile

The EC2 instance has an IAM role (not access keys) that grants:
- `AmazonSSMManagedInstanceCore` — SSM Session Manager access
- `CloudWatchAgentServerPolicy` — CloudWatch logs
- Custom S3 read policy — scoped to content bucket only

**No EC2 instance has access keys stored on disk.**

### Terraform State Bucket

- Bucket policy enforces HTTPS only
- State files encrypted at rest (AES-256)
- Versioning enabled — accidental state deletion is recoverable
- DynamoDB table prevents concurrent state mutations

---

## 2. S3 Security (Solution A)

| Control | Implementation |
|---------|---------------|
| Block public access | All four `block_public_*` settings enabled |
| No public bucket ACL | `acl` argument not used |
| OAC instead of OAI | `aws_cloudfront_origin_access_control` |
| Encryption at rest | SSE-S3 (AES-256) |
| Versioning | Enabled — allows content rollback |
| HTTPS policy | Bucket policy denies non-HTTPS |

### The OAC Bucket Policy Pattern

```json
{
  "Principal": { "Service": "cloudfront.amazonaws.com" },
  "Condition": {
    "StringEquals": {
      "AWS:SourceArn": "arn:aws:cloudfront::ACCOUNT:distribution/DIST_ID"
    }
  }
}
```

This is more restrictive than the legacy OAI pattern — it pins the permission to a specific distribution ID, not just any CloudFront distribution in the account.

---

## 3. CloudFront Security (Solution A)

- `viewer_protocol_policy = "redirect-to-https"` — HTTP always redirected to HTTPS
- `minimum_protocol_version = "TLSv1.2_2021"` — disables TLS 1.0 and 1.1
- `ssl_support_method = "sni-only"` — SNI is the standard; avoids $600/month dedicated IP cost
- Custom error pages — 403/404 serve controlled responses, not AWS defaults

---

## 4. EC2 Security (Solution B)

### Security Groups

```
Internet
    │ HTTPS/HTTP
    ▼
ALB Security Group     (allows 0.0.0.0/0 → 443, 80)
    │ HTTP only
    ▼
EC2 Security Group     (allows ALB SG → 80 only)
    │
    ▼ No inbound from internet
EC2 Instance           (private subnet)
```

EC2 has **no inbound rules from the internet**. All traffic flows through the ALB.

### IMDSv2 Enforcement

IMDSv2 (requiring a session token for metadata access) is enforced on all instances:

```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"   # Forces IMDSv2
  http_put_response_hop_limit = 1            # Prevents SSRF from containers
}
```

Without IMDSv2, an SSRF vulnerability in a web application could steal instance credentials from `http://169.254.169.254`.

### No SSH Port 22

Port 22 is **not opened** in any security group. Access is via:
- **SSM Session Manager** — browser or CLI, fully audited, no key management
- Requires `AmazonSSMManagedInstanceCore` IAM policy on instance role

```powershell
# Start SSM session (no SSH needed)
aws ssm start-session --target i-0abcdef1234567890 --profile dev
```

### Encrypted Root Volume

All EC2 root volumes use `encrypted = true`. This protects data at rest if the underlying hardware is decommissioned.

---

## 5. TLS/HTTPS Configuration

### Solution A — CloudFront + ACM

ACM certificates in `us-east-1` are used by CloudFront (AWS constraint). DNS validation is used — it auto-renews before expiry without requiring site availability.

CloudFront enforces TLS 1.2 minimum with the `TLSv1.2_2021` security policy.

### Solution B — ALB + ACM

ALB uses `ELBSecurityPolicy-TLS13-1-2-2021-06` — the most current AWS managed TLS policy. This:
- Prefers TLS 1.3
- Falls back to TLS 1.2
- Disables all cipher suites below TLS 1.2

ALB terminates TLS. Traffic from ALB to EC2 is HTTP on port 80 (internal VPC only — acceptable since VPC traffic is isolated and not traversing the internet).

---

## 6. Secrets Management

### What is and isn't in version control

| Item | In Git? | Why |
|------|---------|-----|
| Terraform code | ✅ Yes | Infrastructure as code |
| `terraform.tfvars` | ✅ Yes | Non-sensitive config only |
| AWS account IDs | ✅ Yes | Not sensitive — account IDs are visible in ARNs and billing |
| AWS access keys | ❌ Never | Stored in GitHub Secrets only |
| IAM role ARNs | GitHub Secrets | Rotated per environment |
| SSH private keys | ❌ Never | Not used — SSM only |
| `*.tfstate` files | ❌ Never | Contain sensitive resource metadata |
| `*.tfplan` files | ❌ Never | Transient — not persisted |

### `.gitignore` entries

```gitignore
# Terraform
*.tfstate
*.tfstate.backup
*.tfplan
.terraform/
.terraform.lock.hcl    # Commit this — it pins provider versions
override.tf
override.tf.json
*_override.tf
crash.log

# AWS
.aws/credentials       # Never commit credentials
```

---

## 7. Recommendations for Hiring Manager Review

These controls go beyond minimum viable security and signal senior-level thinking:

1. **GitHub OIDC** instead of stored access keys
2. **OAC** instead of deprecated OAI for CloudFront
3. **IMDSv2 enforcement** on every EC2 instance
4. **SSM Session Manager** instead of port 22
5. **State bucket policy** enforcing TLS
6. **DynamoDB state locking** prevents concurrent corruption
7. **ALB TLS 1.3 policy** — latest AWS managed security policy
8. **Private subnets** for EC2 — traffic only via ALB
9. **Separate state per environment** — blast radius containment
10. **`prevent_destroy = true`** on state bucket — prevents accidental wipe

**Optional enhancements for extra credit:**
- WAF on CloudFront (AWS Managed Rules — common web attack protection)
- VPC Flow Logs to S3 or CloudWatch
- AWS Config rules for continuous compliance
- GuardDuty for threat detection
- AWS SecurityHub for centralised findings
