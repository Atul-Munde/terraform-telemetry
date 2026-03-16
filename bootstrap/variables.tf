variable "aws_region" {
  description = "AWS region where S3 bucket and DynamoDB table are created"
  type        = string
  default     = "ap-south-1"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state. Must be globally unique."
  type        = string
  default     = "otel-terraform-state-setup"
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table for Terraform state locking"
  type        = string
  default     = "terraform-state-lock"
}
