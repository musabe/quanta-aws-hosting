# modules/route53/main.tf
# Creates DNS records for both solution types.
# Uses ALIAS records (not CNAME) for root domains — AWS best practice.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_route53_zone" "this" {
  name         = var.hosted_zone_name
  private_zone = false
}

# ALIAS record — used for CloudFront (Solution A) or ALB (Solution B)
# WHY ALIAS over CNAME: ALIAS works at zone apex (example.com), CNAME does not.
# ALIAS also has no extra DNS query charge.
resource "aws_route53_record" "alias" {
  count = var.create_alias_record ? 1 : 0

  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.record_name
  type    = "A"

  alias {
    name                   = var.alias_target_dns_name
    zone_id                = var.alias_target_hosted_zone_id
    evaluate_target_health = var.evaluate_target_health
  }
}

# IPv6 ALIAS record
resource "aws_route53_record" "alias_ipv6" {
  count = var.create_alias_record && var.enable_ipv6 ? 1 : 0

  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.record_name
  type    = "AAAA"

  alias {
    name                   = var.alias_target_dns_name
    zone_id                = var.alias_target_hosted_zone_id
    evaluate_target_health = var.evaluate_target_health
  }
}
