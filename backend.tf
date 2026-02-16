# Configure remote state backend
# Production S3 backend configuration

terraform {
  backend "s3" {
    bucket         = "otel-terraform-state-setup"
    key            = "k8s-otel-jaeger/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
    profile        = "mum-test"
  }
}

# Alternative: Using Terraform Cloud
# terraform {
#   backend "remote" {
#     organization = "your-org"
#     workspaces {
#       name = "k8s-otel-jaeger"
#     }
#   }
# }

# Alternative: Using GCS for GCP
# terraform {
#   backend "gcs" {
#     bucket = "your-terraform-state-bucket"
#     prefix = "k8s-otel-jaeger"
#   }
# }

# Alternative: Using Azure Storage
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "terraform-state-rg"
#     storage_account_name = "tfstate"
#     container_name       = "tfstate"
#     key                  = "k8s-otel-jaeger.tfstate"
#   }
# }
