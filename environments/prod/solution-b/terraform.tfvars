# environments/prod/solution-b/terraform.tfvars

environment       = "prod"
project_name      = "quanta-aws-hosting"
aws_profile       = "quanta-web-prod"
aws_region        = "us-east-1"
domain_name       = "ec2.quantaweb.dev"
hosted_zone_name  = "quantaweb.dev"
vpc_cidr          = "10.1.0.0/16"
instance_type     = "t3.small"
content_s3_bucket = "quanta-aws-hosting-content-prod-390951754623"
