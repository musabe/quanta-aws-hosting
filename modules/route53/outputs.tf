# modules/route53/outputs.tf

output "zone_id" {
  value = data.aws_route53_zone.this.zone_id
}

output "record_fqdn" {
  value = var.create_alias_record ? aws_route53_record.alias[0].fqdn : ""
}
