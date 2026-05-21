# Security

This document describes the security controls implemented across the quanta-aws-hosting project. The design applies defence in depth — multiple independent controls across IAM, network, data, and operational layers — so that a failure in any single control does not compromise the overall system.

---

## 🔐 IAM Strategy

### GitHub Actions OIDC Federation

> [!IMPORTANT]
> No long-lived AWS credentials are stored anywhere in this repository or GitHub Secrets.

GitHub Actions authenticates to AWS via OIDC federation using short-lived tokens:

```
GitHub Actions job
    │ Requests OIDC token from GitHub
    ▼
token.actions.githubusercontent.com
    │ Returns signed JWT:
    │   sub: repo:musabe/quanta-aws-hosting:ref:refs/heads/main
    ▼
AWS STS AssumeRoleWithWebIdentity
    │ Validates JWT signature and trust policy conditions
    ▼
Temporary credentials (15-minute TTL)
```

The IAM role trust policy restricts assumption to the specific GitHub repository and optionally a specific branch. OIDC tokens expire automatically and cannot be reused.

**Why it matters:** Long-lived access keys remain valid until manually rotated. A leaked OIDC token expires within 15 minutes and is scoped to a single workflow run.

### Bootstrap vs Day-2 IAM

`AdministratorAccess` is used only during the initial bootstrap step to create the remote state infrastructure and OIDC provider. All ongoing deployments use the scoped `quanta-aws-hosting-github-actions-{env}` IAM role with least-privilege permissions covering only the services required.

### EC2 Instance Profile

EC2 instances use an IAM instance role — no access keys are stored on disk. The role grants:

- `AmazonSSMManagedInstanceCore` — SSM Session Manager access
- `CloudWatchAgentServerPolicy` — CloudWatch Logs shipping
- Custom S3 read policy — scoped to the content bucket only

### Terraform State Bucket

- Bucket policy enforces HTTPS-only access
- AES-256 server-side encryption at rest
- Versioning enabled — accidental deletion is recoverable
- DynamoDB table prevents concurrent state mutations

---

## ☁️ S3 Security (Solution A)

| Control | Implementation |
|---------|---------------|
| Block public access | All four `block_public_*` settings enabled |
| Public ACL | Not used — `acl` argument omitted |
| Origin access | OAC (`aws_cloudfront_origin_access_control`) |
| Encryption at rest | SSE-S3 (AES-256) |
| Versioning | Enabled — supports content rollback |
| Transport security | Bucket policy denies non-HTTPS requests |

### OAC Bucket Policy Pattern

The bucket policy pins access to a specific CloudFront distribution ARN:

```json
{
  "Principal": { "Service": "cloudfront.amazonaws.com" },
  "Condition": {
    "StringEquals": {
      "AWS:SourceArn": "arn:aws:cloudfront::111111111111:distribution/EXAMPLE"
    }
  }
}
```

This is more restrictive than the legacy OAI pattern, which allowed any CloudFront distribution in the account to access the bucket.

---

## 🌐 CloudFront Security (Solution A)

- `viewer_protocol_policy = "redirect-to-https"` — all HTTP traffic redirected to HTTPS
- `minimum_protocol_version = "TLSv1.2_2021"` — TLS 1.0 and 1.1 disabled
- `ssl_support_method = "sni-only"` — SNI-based TLS; avoids the $600/month dedicated IP option
- Custom error responses — 403 and 404 return controlled pages, not raw AWS error responses

---

## 🖥️ EC2 Security (Solution B)

### Security Group Layering

```
Internet
    │ HTTPS / HTTP
    ▼
ALB Security Group       (ingress: 0.0.0.0/0 → 443, 80)
    │ HTTP:80 only
    ▼
EC2 Security Group       (ingress: ALB SG reference → 80)
    │
    ▼ No direct inbound from internet
EC2 Instance             (private subnet)
```

EC2 accepts inbound traffic only from the ALB security group — not from any CIDR range. This ensures the ALB is the only path to the instance.

**Why security group references over CIDR:** CIDR-based ingress rules are static and cannot track ALB IP changes. Security group references follow the ALB automatically.

### IMDSv2 Enforcement

All EC2 instances enforce IMDSv2:

```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"
  http_put_response_hop_limit = 1
}
```

**Why it matters:** Without IMDSv2, an SSRF vulnerability in a web application can fetch instance credentials from `http://169.254.169.254` with a simple HTTP request. IMDSv2 requires a session token that cannot be obtained via SSRF.

### No SSH Exposure

Port 22 is not opened in any security group. Management access uses SSM Session Manager:

```powershell
aws ssm start-session --target i-EXAMPLE --profile quanta-web-prod
```

**Why it matters:** SSM requires no inbound firewall rule, produces a full audit trail in CloudTrail, and eliminates SSH key management entirely.

### Encrypted Root Volumes

All EC2 root volumes use `encrypted = true` with gp3 storage. This protects data at rest if underlying hardware is decommissioned.

### ALB-to-EC2 Traffic

ALB terminates TLS and forwards HTTP:80 to EC2 internally. This traffic remains inside the isolated VPC and does not traverse the public internet. Adding HTTPS between ALB and EC2 is possible if compliance requirements demand it, at the cost of certificate management on instances.

---

## 🔑 Secrets Management

### Version Control Policy

| Item | In Git? | Reason |
|------|---------|--------|
| Terraform code | ✅ Yes | Infrastructure as code |
| `terraform.tfvars` | ✅ Yes | Non-sensitive configuration only |
| AWS access keys | ❌ Never | Not used — OIDC only |
| IAM role ARNs | GitHub Secrets | Per-environment, not committed |
| SSH private keys | ❌ Never | Not used — SSM only |
| `*.tfstate` files | ❌ Never | Contain sensitive resource metadata |
| `*.tfplan` files | ❌ Never | Transient — not persisted to Git |

### `.gitignore` Entries

```gitignore
*.tfstate
*.tfstate.backup
*.tfplan
.terraform/
crash.log
.aws/credentials
```

---

## 🛡️ Threat Model Considerations

| Threat | Mitigation |
|--------|-----------|
| Credential leakage | OIDC federation — no persistent credentials exist |
| SSRF attacks on EC2 | IMDSv2 enforcement — session token required |
| Direct EC2 access | Private subnets + no port 22 + SSM only |
| S3 data exposure | Block public access + OAC + HTTPS-only bucket policy |
| Dev/prod blast radius | Separate AWS accounts with independent IAM boundaries |
| Concurrent state corruption | DynamoDB state locking |
| Accidental state deletion | S3 versioning on state bucket |

---

## 🔒 Security Posture Summary

This implementation demonstrates:

- **Credential minimization** — no long-lived keys anywhere in the CI/CD pipeline
- **Reduced attack surface** — private subnets, no SSH, no public S3 access
- **Least privilege** — scoped IAM roles per environment and service
- **Blast radius containment** — separate AWS accounts, separate state, separate IAM

**Production enhancements worth adding:**
- WAF with AWS Managed Rules on CloudFront
- VPC Flow Logs to S3 or CloudWatch
- AWS GuardDuty for threat detection
- AWS Config rules for continuous compliance
- AWS SecurityHub for centralised findings aggregation
