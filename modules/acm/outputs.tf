# modules/acm/outputs.tf

output "certificate_arn" {
  description = "ACM certificate ARN — pass to CloudFront or ALB"
  value       = aws_acm_certificate_validation.this.certificate_arn
}
