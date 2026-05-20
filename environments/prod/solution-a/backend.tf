# environments/prod/solution-a/backend.tf
terraform {
  backend "s3" {
    bucket         = "quanta-aws-hosting-tfstate-prod-390951754623"
    key            = "prod/solution-a/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "quanta-aws-hosting-tflock-prod"
    encrypt        = true
    profile        = "quanta-web-prod"
  }
}
