# environments/dev/solution-b/terraform.tfvars

environment       = "dev"
project_name      = "quanta-aws-hosting"
aws_profile       = "quanta-web-dev"
aws_region        = "us-east-1"
domain_name       = "ec2.quantadev.dev"
hosted_zone_name  = "quantadev.dev"
vpc_cidr          = "10.0.0.0/16"
instance_type     = "t3.micro"
content_s3_bucket = "quanta-aws-hosting-content-dev-858371255598"
