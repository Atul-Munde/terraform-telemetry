# =============================================================================
# Bootstrap — Terraform Remote State Infrastructure
# =============================================================================
# Run this ONCE before any environment's `terraform init`.
# It creates the S3 bucket and DynamoDB table that all environments use
# as their Terraform backend.
#
# Uses a LOCAL backend (no S3 yet) — state is stored in bootstrap/terraform.tfstate
# Keep that file safe or re-run bootstrap to recreate resources.
#
# Usage:
#   cd bootstrap
#   AWS_PROFILE=<your-profile> terraform init
#   AWS_PROFILE=<your-profile> terraform apply
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # LOCAL backend — intentional. S3 bucket doesn't exist yet.
  # After apply, all other environments use the S3 backend this creates.
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
  # profile set via AWS_PROFILE env var
}

# -----------------------------------------------------------------------------
# S3 Bucket for Terraform State
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name

  tags = {
    Name        = var.state_bucket_name
    Purpose     = "terraform-state"
    ManagedBy   = "terraform-bootstrap"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90   # keep 90 days of old state versions
    }
  }
}

# -----------------------------------------------------------------------------
# DynamoDB Table for State Locking
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "terraform_lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"  # no capacity planning needed
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name      = var.lock_table_name
    Purpose   = "terraform-state-lock"
    ManagedBy = "terraform-bootstrap"
  }
}
