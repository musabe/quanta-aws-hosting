# environments/prod/solution-a/variables.tf

variable "environment"            { type = string; default = "prod" }
variable "project_name"           { type = string; default = "quanta-aws-hosting" }
variable "aws_profile"            { type = string; default = "quanta-web-prod" }
variable "domain_name"            { type = string }
variable "hosted_zone_name"       { type = string }
variable "cloudfront_price_class" { type = string; default = "PriceClass_All" }
