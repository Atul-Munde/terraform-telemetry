# Shared Backend Configuration Template
# Copy this to environments/{env}/backend.tf and replace ${environment}

terraform {
  backend "s3" {
    bucket         = "otel-terraform-state-setup"
    key            = "k8s-otel-jaeger/${environment}/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-state-lock-${environment}"
    encrypt        = true
  }
}

# Note: Each environment should have its own DynamoDB table to prevent lock contention
# Create tables with: aws dynamodb create-table --table-name terraform-state-lock-{env} ...
