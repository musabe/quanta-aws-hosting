# environments/prod/solution-a/outputs.tf

output "bucket_id"                { value = module.s3_cloudfront.bucket_id }
output "distribution_id"          { value = module.s3_cloudfront.distribution_id }
output "distribution_domain_name" { value = module.s3_cloudfront.distribution_domain_name }
output "domain_name"              { value = var.domain_name }
