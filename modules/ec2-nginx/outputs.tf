# modules/ec2-nginx/outputs.tf

output "alb_dns_name" {
  description = "ALB DNS name — use as ALIAS target in Route53"
  value       = aws_lb.this.dns_name
}

output "alb_hosted_zone_id" {
  description = "ALB hosted zone ID — needed for Route53 ALIAS record"
  value       = aws_lb.this.zone_id
}

output "instance_id" {
  description = "EC2 instance ID — used for SSM commands and redeployment"
  value       = aws_instance.web.id
}

output "alb_arn" {
  value = aws_lb.this.arn
}
