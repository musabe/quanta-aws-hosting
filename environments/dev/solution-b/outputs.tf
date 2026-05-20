# environments/dev/solution-b/outputs.tf

output "instance_id"  { value = module.ec2_nginx.instance_id }
output "alb_dns_name" { value = module.ec2_nginx.alb_dns_name }
output "domain_name"  { value = var.domain_name }
