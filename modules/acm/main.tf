# modules/acm/main.tf
# Issues and validates an ACM certificate via DNS validation.
# WHY DNS validation: HTTP validation requires the site to be live first.
# DNS validation works before deployment and auto-renews.
# IMPORTANT: This module must be deployed in us-east-1 for CloudFront.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  # Best practice: create new cert before destroying old one
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = var.domain_name
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create Route53 validation records
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

# Wait for certificate validation to complete
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  # ACM validation can take up to 30 minutes — Terraform waits automatically
  timeouts {
    create = "45m"
  }
}
