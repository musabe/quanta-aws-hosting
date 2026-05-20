# modules/route53/variables.tf

variable "hosted_zone_name" {
  description = "Route53 hosted zone name (e.g. example.com)"
  type        = string
}

variable "record_name" {
  description = "DNS record name — empty string for zone apex, subdomain for others"
  type        = string
  default     = ""
}

variable "alias_target_dns_name" {
  description = "DNS name of the ALIAS target (CloudFront domain or ALB DNS name)"
  type        = string
}

variable "alias_target_hosted_zone_id" {
  description = "Hosted zone ID of the ALIAS target"
  type        = string
}

variable "create_alias_record" {
  description = "Whether to create the ALIAS record"
  type        = bool
  default     = true
}

variable "evaluate_target_health" {
  description = "Whether Route53 health checks evaluate ALB target health"
  type        = bool
  default     = false
}

variable "enable_ipv6" {
  description = "Create AAAA record for IPv6"
  type        = bool
  default     = true
}
