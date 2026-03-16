output "state_bucket_name" {
  description = "S3 bucket name — use this in environments/{env}/main.tf backend block"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "state_bucket_arn" {
  description = "S3 bucket ARN — use in IAM policies for CI/CD role"
  value       = aws_s3_bucket.terraform_state.arn
}

output "lock_table_name" {
  description = "DynamoDB table name — use this in environments/{env}/main.tf backend block"
  value       = aws_dynamodb_table.terraform_lock.name
}

output "lock_table_arn" {
  description = "DynamoDB table ARN — use in IAM policies for CI/CD role"
  value       = aws_dynamodb_table.terraform_lock.arn
}

output "next_steps" {
  description = "What to do after bootstrap apply"
  value = <<-EOT
    Bootstrap complete. Now run in each environment:

      cd environments/staging
      AWS_PROFILE=<your-profile> terraform init

    Backend config already set in each environment's main.tf:
      bucket         = "${aws_s3_bucket.terraform_state.bucket}"
      dynamodb_table = "${aws_dynamodb_table.terraform_lock.name}"
      region         = "${aws_s3_bucket.terraform_state.region}"
  EOT
}
