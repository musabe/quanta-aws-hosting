# bootstrap/outputs.tf

output "state_bucket_name" {
  value = aws_s3_bucket.terraform_state.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.terraform_locks.name
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_deploy.arn
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "next_steps" {
  value = <<-EOT

    ✅ Bootstrap complete for ${var.environment}!

    Add this to GitHub Secrets:
      AWS_ROLE_ARN_${upper(var.environment)} = ${aws_iam_role.github_actions_deploy.arn}

    State bucket : ${aws_s3_bucket.terraform_state.id}
    Lock table   : ${aws_dynamodb_table.terraform_locks.name}
  EOT
}
