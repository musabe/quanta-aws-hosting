# environments/dev/solution-a/main.tf

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "us-east-1"

  default_tags {
    tags = {
      ManagedBy  = "Terraform"
      Environment = var.environment
      Project     = var.project_name
      Solution    = "solution-a"
      Repository  = "musabe/quanta-aws-hosting"
    }
  }
}

data "aws_caller_identity" "current" {}

module "acm" {
  source                    = "../../../modules/acm"
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  route53_zone_id           = module.route53.zone_id
  environment               = var.environment
  project_name              = var.project_name
}

module "s3_cloudfront" {
  source                 = "../../../modules/s3-cloudfront"
  project_name           = var.project_name
  environment            = var.environment
  bucket_name            = "quanta-aws-hosting-website-dev-${data.aws_caller_identity.current.account_id}"
  domain_name            = var.domain_name
  acm_certificate_arn    = module.acm.certificate_arn
  cloudfront_price_class = var.cloudfront_price_class
}

module "route53" {
  source                      = "../../../modules/route53"
  hosted_zone_name            = var.hosted_zone_name
  record_name                 = ""
  alias_target_dns_name       = module.s3_cloudfront.distribution_domain_name
  alias_target_hosted_zone_id = module.s3_cloudfront.distribution_hosted_zone_id
  enable_ipv6                 = true
}
