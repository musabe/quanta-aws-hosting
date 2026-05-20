# modules/acm/variables.tf

variable "domain_name" {
  description = "Primary domain name for the certificate"
  type        = string
}

variable "subject_alternative_names" {
  description = "Additional domain names to include in the certificate"
  type        = list(string)
  default     = []
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS validation records"
  type        = string
}

variable "environment" {
  type = string
}

variable "project_name" {
  type = string
}
