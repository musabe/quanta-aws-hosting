variable "environment" {
  type    = string
  default = "dev"
}

variable "project_name" {
  type    = string
  default = "quanta-aws-hosting"
}

variable "aws_profile" {
  type    = string
  default = "quanta-web-dev"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "domain_name" {
  type = string
}

variable "hosted_zone_name" {
  type = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "content_s3_bucket" {
  type = string
}