# environments/dev/solution-b/backend.tf
terraform {
  backend "s3" {
    bucket         = "quanta-aws-hosting-tfstate-dev-858371255598"
    key            = "dev/solution-b/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "quanta-aws-hosting-tflock-dev"
    encrypt        = true
    profile        = "quanta-web-dev"
  }
}
