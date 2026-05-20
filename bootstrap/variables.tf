# bootstrap/variables.tf

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_profile" {
  type = string
}

variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Must be dev or prod."
  }
}
