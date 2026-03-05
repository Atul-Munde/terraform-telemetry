# S3 Bucket + IAM IRSA for vmbackup
# Creates a private, encrypted, versioned S3 bucket and wires it to a
# Kubernetes ServiceAccount via IRSA (IAM Roles for Service Accounts).
# The vmbackup CronJob in backup.tf uses this service account.

locals {
  # Extract the OIDC provider URL from the ARN:
  #   arn:aws:iam::123456789:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/XXXXX
  #                                        ^ this part is the URL used in the condition
  oidc_provider_url = var.backup_enabled && var.eks_oidc_provider_arn != "" ? regex("oidc-provider/(.+)$", var.eks_oidc_provider_arn)[0] : ""
}

# ---------------------------------------------------------------------------
# S3 Bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "vmbackup" {
  count = var.backup_enabled ? 1 : 0

  bucket        = local.s3_bucket_name
  force_destroy = false

  tags = merge(local.common_labels, {
    Name    = local.s3_bucket_name
    Purpose = "victoria-metrics-backup"
  })
}

resource "aws_s3_bucket_versioning" "vmbackup" {
  count = var.backup_enabled ? 1 : 0

  bucket = aws_s3_bucket.vmbackup[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vmbackup" {
  count = var.backup_enabled ? 1 : 0

  bucket = aws_s3_bucket.vmbackup[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "vmbackup" {
  count = var.backup_enabled ? 1 : 0

  bucket                  = aws_s3_bucket.vmbackup[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle: expire backup objects after var.backup_retention_days to control cost
resource "aws_s3_bucket_lifecycle_configuration" "vmbackup" {
  count = var.backup_enabled ? 1 : 0

  bucket = aws_s3_bucket.vmbackup[0].id

  rule {
    id     = "expire-backups"
    status = "Enabled"

    filter {
      prefix = "backups/"
    }

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# ---------------------------------------------------------------------------
# IAM Role (IRSA) — trust the vmbackup ServiceAccount via OIDC
# ---------------------------------------------------------------------------
resource "aws_iam_role" "vmbackup" {
  count = var.backup_enabled && var.eks_oidc_provider_arn != "" ? 1 : 0

  name        = "vm-backup-${var.environment}"
  description = "IRSA role for VictoriaMetrics vmbackup — grants S3 access to the vmbackup CronJob"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.eks_oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider_url}:sub" = "system:serviceaccount:${var.namespace}:vmbackup"
            "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(local.common_labels, {
    Name = "vm-backup-${var.environment}"
  })
}

resource "aws_iam_role_policy" "vmbackup" {
  count = var.backup_enabled && var.eks_oidc_provider_arn != "" ? 1 : 0

  name   = "vm-backup-s3-policy"
  role   = aws_iam_role.vmbackup[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload"
        ]
        Resource = "${aws_s3_bucket.vmbackup[0].arn}/backups/*"
      },
      {
        Sid    = "S3ListBucket"
        Effect = "Allow"
        Action = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.vmbackup[0].arn
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Kubernetes ServiceAccount annotated with IRSA role ARN
# ---------------------------------------------------------------------------
resource "kubernetes_service_account" "vmbackup" {
  count = var.backup_enabled ? 1 : 0

  metadata {
    name      = "vmbackup"
    namespace = var.namespace
    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "vmbackup"
    })
    annotations = var.eks_oidc_provider_arn != "" ? {
      "eks.amazonaws.com/role-arn" = aws_iam_role.vmbackup[0].arn
    } : {}
  }
}
