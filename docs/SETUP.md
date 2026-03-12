# Setup Guide

Initial setup for working with this Terraform repository.

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Terraform | >= 1.5 | https://developer.hashicorp.com/terraform/install |
| kubectl | any recent | https://kubernetes.io/docs/tasks/tools/ |
| Helm | >= 3.12 | https://helm.sh/docs/intro/install/ |
| AWS CLI v2 | any | https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html |

---

## AWS Configuration

```bash
# Configure mum-test profile
aws configure --profile mum-test
# AWS Access Key ID: <your key>
# AWS Secret Access Key: <your secret>
# Default region: ap-south-1
# Default output format: json

# Verify EKS access
aws eks describe-cluster --name intangles-qa-cluster --region ap-south-1 --profile mum-test
```

## kubectl Access

```bash
aws eks update-kubeconfig \
  --region ap-south-1 \
  --name intangles-qa-cluster \
  --profile mum-test

kubectl get nodes
```

---

## Terraform Backend

The state is stored in S3. On first setup:

```bash
cd environments/staging

terraform init \
  -backend-config="bucket=intangles-tf-state" \
  -backend-config="key=staging/telemetry.tfstate" \
  -backend-config="region=ap-south-1"
```

---

## Credentials

Two sensitive values must be provided at apply time via environment variables:

| Variable | Description |
|----------|-------------|
| `TF_VAR_elastic_password` | Elasticsearch `elastic` superuser password |
| `TF_VAR_kibana_encryption_key` | Kibana saved-objects encryption key (exactly 32 chars) |

Example:
```bash
export TF_VAR_elastic_password='MySecurePassword2026'
export TF_VAR_kibana_encryption_key='MySecureKibanaKey2026RandomXXXXX'
```

**Never commit these to `terraform.tfvars`.**

---

## Terraform Providers

All providers are pinned in `versions.tf`:

```hcl
required_providers {
  kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.25" }
  helm       = { source = "hashicorp/helm",       version = "~> 2.12" }
  kubectl    = { source = "gavinbunney/kubectl",  version = "~> 1.14" }
  aws        = { source = "hashicorp/aws",        version = "~> 5.0"  }
  tls        = { source = "hashicorp/tls",        version = ">= 4.0"  }
}
```

`terraform init` downloads all providers automatically.

---

## First Deploy

```bash
cd environments/staging

TF_VAR_elastic_password='<password>' \
TF_VAR_kibana_encryption_key='<32-char-key>' \
terraform apply -auto-approve
```

First deploy takes ~5–10 minutes (Elasticsearch cluster startup, VictoriaMetrics PVC provisioning).

---

## Working with Multiple Environments

Each environment is isolated:

```bash
# Staging
cd environments/staging && terraform init ... && terraform apply ...

# Production
cd environments/production && terraform init ... && terraform apply ...
```

Shared module code lives in `modules/`. Per-environment config is in `terraform.tfvars`.
