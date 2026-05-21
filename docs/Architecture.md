# Architecture

## Part 1 — Architecture Research & Decision Matrix

### Candidates Evaluated

| Approach | Cost (monthly est.) | Ops Complexity | Scalability | TF Support | CI/CD | Production Ready |
|----------|-------------------|----------------|-------------|------------|-------|-----------------|
| S3 + CloudFront | $1–$15 | Low | Infinite | Excellent | Excellent | ✅ |
| EC2 + Nginx | $8–$40 | Medium | Manual | Excellent | Good | ✅ |
| ECS/Fargate | $15–$80 | High | Auto | Excellent | Good | ✅ |
| Amplify | $0–$20 | Very Low | Auto | Limited | Built-in | ⚠️ Limited control |
| Elastic Beanstalk | $10–$50 | Medium | Semi-auto | Partial | Moderate | ⚠️ Legacy |

---

### 1. S3 + CloudFront

**Advantages**
- Near-zero operational overhead; no servers to patch
- Global CDN built-in (400+ edge locations)
- Pay-per-request pricing — extremely cost-efficient for low/medium traffic
- Terraform support is first-class and stable
- Cache invalidation integrates cleanly with GitHub Actions
- Scales to millions of requests without configuration changes

**Disadvantages**
- Static content only — no server-side rendering at the edge without Lambda@Edge
- Cache invalidation adds latency to deployments (typically 30–60s)
- CloudFront behaviour rules require careful ordering

**Cost implications**
- S3: ~$0.023/GB storage + $0.0004/10k GET requests
- CloudFront: ~$0.0085/GB data transfer (US/EU)
- ACM: Free
- Route53: $0.50/hosted zone + $0.40/million queries
- **Realistic monthly cost: $1–$15 for a typical static site**

**Security**
- OAC (Origin Access Control) prevents direct S3 access
- No public bucket ACLs needed
- WAF integrable at CloudFront layer
- TLS 1.2+ enforced by CloudFront viewer policy

**Terraform compatibility: ★★★★★**
All resources (`aws_s3_bucket`, `aws_cloudfront_distribution`, `aws_acm_certificate`, `aws_route53_record`) have mature, stable providers.

---

### 2. EC2 + Nginx

**Advantages**
- Full server control — custom modules, headers, rewrite rules
- Supports dynamic content, reverse proxy, server-side logic
- Familiar operational model for most teams
- Elastic IP provides stable endpoint across instance replacements
- SSH access for live debugging

**Disadvantages**
- Requires OS patching, security updates
- Single point of failure without ALB + ASG
- Scaling requires additional configuration
- Higher baseline cost even at idle

**Cost implications**
- t3.micro: ~$8.50/month (or free tier eligible)
- Elastic IP: Free while attached, $0.005/hr when unattached
- ALB: ~$16/month base + LCU charges
- **Realistic monthly cost: $25–$45 with ALB**

**Security**
- Security Groups as instance firewall
- SSH should use key pairs, ideally SSM Session Manager (no port 22 needed)
- ALB terminates TLS, backend can use HTTP internally
- IMDSv2 enforced on instance metadata

**Terraform compatibility: ★★★★☆**
Mature provider support; user_data bootstrapping is the main complexity.

---

### 3. ECS/Fargate

**Advantages**
- Containerised workloads with no EC2 management
- Rolling deployments, health checks, task definitions version-controlled

**Disadvantages**
- Significant complexity overhead for a simple website
- Cold starts on scale-to-zero
- Overkill for static or simple dynamic sites
- Longer Terraform code surface area

**Decision: Rejected.** ECS is the right choice for microservices. For this challenge it introduces unnecessary complexity without demonstrating cleaner patterns.

---

### 4. AWS Amplify

**Advantages**
- Zero infrastructure to manage
- Git-push deploys out of the box

**Disadvantages**
- Black-box infrastructure — cannot demonstrate Terraform skills
- Limited customisation of CDN behaviour
- Not suitable for demonstrating infrastructure engineering

**Decision: Rejected.** Amplify obscures the infrastructure layer entirely. A job application challenge requires demonstrating explicit infrastructure decisions.

---

### 5. Elastic Beanstalk

**Advantages**
- PaaS abstraction over EC2 + ALB + ASG

**Disadvantages**
- Terraform support is incomplete (EB environments have known drift issues)
- Considered a legacy AWS service — most teams are migrating away
- Cannot demonstrate fine-grained infrastructure control

**Decision: Rejected.** Beanstalk is opinionated in ways that conflict with clean Terraform workflows.

---

## Final Selection

**Solution A: S3 + CloudFront** — chosen for:
1. Lowest operational burden, highest scalability — excellent production profile
2. Best demonstration of CloudFront OAC, ACM validation, and S3 security hardening
3. Cleanest CI/CD story (S3 sync + invalidation)

**Solution B: EC2 + Nginx** — chosen for:
1. Demonstrates VPC design, security groups, ALB, and IAM instance profiles
2. Shows traditional server skills alongside modern IaC
3. Elastic IP + DNS demonstrates stable endpoint management

Together, the two solutions cover the full spectrum from serverless-static to traditional-compute, demonstrating architectural range.

---

## Solution A — S3 + CloudFront Architecture

![Solution A — S3 + CloudFront](images/SolutionA-S3-CloudFront.png)

### Flow
1. User browser makes HTTPS request to `quantaweb.dev`
2. Route53 ALIAS record resolves to CloudFront distribution
3. CloudFront validates TLS using ACM certificate (us-east-1)
4. CloudFront checks edge cache — serves cached response if available
5. On cache miss, CloudFront signs request via OAC and fetches from S3
6. S3 returns object — CloudFront caches and serves to user
7. HTTP requests are automatically redirected to HTTPS by CloudFront

### CI/CD Flow
1. `terraform fmt` / `validate` / `plan` on every PR
2. `terraform apply` on merge to `main` or `develop`
3. `aws s3 sync` uploads updated website files
4. `aws cloudfront create-invalidation` purges edge caches

---

## Solution B — EC2 + Nginx + ALB Architecture

![Solution B — EC2 + Nginx + ALB](images/SolutionB-EC2-Nginx-ALB.png)

### Flow
1. User browser makes HTTPS request to `ec2.quantaweb.dev`
2. Route53 ALIAS record resolves to ALB DNS name
3. ALB terminates TLS using ACM certificate
4. ALB forwards HTTP:80 traffic to EC2 target group (private subnet)
5. EC2 security group only accepts traffic from ALB security group
6. Nginx serves static content from `/var/www/html`
7. HTTP:80 requests to ALB are redirected to HTTPS:443

### CI/CD Flow
1. `terraform apply` creates/updates infrastructure
2. GitHub Actions syncs content to S3 content bucket
3. SSM Run Command triggers `aws s3 sync` on EC2
4. Nginx reloads to serve updated content

---

## Key Architecture Decisions

### Why OAC over OAI (Origin Access Identity)?
OAI is deprecated by AWS. OAC (Origin Access Control) is the current recommended pattern. It supports SSE-KMS buckets and provides stronger signing with the distribution ARN pinned in the bucket policy.

### Why ALB over direct EC2 TLS?
- ALB handles TLS termination via ACM — no certificate management on instances
- ALB enables future migration to Auto Scaling Groups without DNS changes
- ALB health checks provide automatic traffic cutover
- Separates the "stable endpoint" from the "compute layer"

### Why us-east-1 for ACM?
CloudFront requires ACM certificates in `us-east-1`. This is an AWS hard constraint. The Route53 hosted zone is global and unaffected by region.

### Why GitHub OIDC over static credentials?
Long-lived AWS access keys stored in GitHub Secrets are a security liability. GitHub OIDC tokens are short-lived (15 minutes), scoped to a specific repository and branch, and automatically rotated. This is the AWS-recommended pattern for CI/CD.

### Why ALIAS records over CNAME?
CNAME records cannot be used at the zone apex (`quantaweb.dev`). ALIAS records work at apex, resolve faster, and have no extra DNS query charge.

### Why separate dev/prod AWS accounts?
Blast radius containment — a `terraform destroy` in dev cannot touch prod. Separate billing visibility and IAM boundaries match how mature engineering teams operate.
