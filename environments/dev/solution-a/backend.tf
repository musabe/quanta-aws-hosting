# environments/dev/solution-a/backend.tf
terraform {
  backend "s3" {
    bucket         = "quanta-aws-hosting-tfstate-dev-239732221791"
    key            = "dev/solution-a/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "quanta-aws-hosting-tflock-dev"
    encrypt        = true
    profile        = "quanta-web-dev"
  }
}
