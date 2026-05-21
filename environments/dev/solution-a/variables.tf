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

variable "domain_name" {
  type = string
}

variable "hosted_zone_name" {
  type = string
}

variable "cloudfront_price_class" {
  type    = string
  default = "PriceClass_100"
}