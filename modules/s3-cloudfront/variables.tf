# modules/s3-cloudfront/variables.tf

variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "Environment (dev/prod)"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket name for website content"
  type        = string
}

variable "domain_name" {
  description = "Primary domain name (e.g. example.com or dev.example.com)"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN — must be in us-east-1 for CloudFront"
  type        = string
}

variable "cloudfront_price_class" {
  description = "CloudFront price class. PriceClass_100 = US+EU only (cheapest)"
  type        = string
  default     = "PriceClass_100"
  validation {
    condition = contains([
      "PriceClass_100",
      "PriceClass_200",
      "PriceClass_All"
    ], var.cloudfront_price_class)
    error_message = "Must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}
