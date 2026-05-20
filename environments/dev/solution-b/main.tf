# environments/dev/solution-b/main.tf

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
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      ManagedBy  = "Terraform"
      Environment = var.environment
      Project     = var.project_name
      Solution    = "solution-b"
      Repository  = "musabe/quanta-aws-hosting"
    }
  }
}

module "vpc" {
  source       = "../../../modules/vpc"
  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
}

module "acm" {
  source                    = "../../../modules/acm"
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  route53_zone_id           = module.route53.zone_id
  environment               = var.environment
  project_name              = var.project_name
}

module "ec2_nginx" {
  source              = "../../../modules/ec2-nginx"
  project_name        = var.project_name
  environment         = var.environment
  aws_region          = var.aws_region
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  private_subnet_ids  = module.vpc.private_subnet_ids
  acm_certificate_arn = module.acm.certificate_arn
  content_s3_bucket   = var.content_s3_bucket
  instance_type       = var.instance_type
}

module "route53" {
  source                      = "../../../modules/route53"
  hosted_zone_name            = var.hosted_zone_name
  record_name                 = "ec2"
  alias_target_dns_name       = module.ec2_nginx.alb_dns_name
  alias_target_hosted_zone_id = module.ec2_nginx.alb_hosted_zone_id
  evaluate_target_health      = true
  enable_ipv6                 = false
}
