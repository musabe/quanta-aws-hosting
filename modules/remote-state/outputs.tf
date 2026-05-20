# modules/remote-state/outputs.tf
output "bucket_id"    { value = aws_s3_bucket.state.id }
output "bucket_arn"   { value = aws_s3_bucket.state.arn }
output "table_name"   { value = aws_dynamodb_table.lock.name }
