# modules/ec2-nginx/variables.tf

variable "project_name"      { type = string }
variable "environment"       { type = string }
variable "aws_region"        { type = string }
variable "vpc_id"            { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "private_subnet_ids"{ type = list(string) }
variable "acm_certificate_arn" { type = string }
variable "content_s3_bucket" {
  description = "S3 bucket containing website content to sync to EC2"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}
