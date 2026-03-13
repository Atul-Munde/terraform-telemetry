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

The backend and AWS provider authenticate via the `AWS_PROFILE` environment variable (or an IAM role in CI). The profile name is **not hardcoded** in any Terraform file — set it in your shell before running any Terraform or AWS CLI command.

```bash
# Create a named AWS profile for this project (one-time setup)
aws configure --profile <your-profile-name>
# AWS Access Key ID: <your key>
# AWS Secret Access Key: <your secret>
# Default region: ap-south-1
# Default output format: json

# Export it for the current shell session
export AWS_PROFILE=<your-profile-name>

# Verify EKS access
aws eks describe-cluster --name intangles-qa-cluster --region ap-south-1
```

> **Why env var, not hardcoded profile?** The `profile` field was removed from `backend.tf` and `environments/staging/main.tf` so engineers use their own local profile names without modifying tracked files. In CI, an IAM role is assumed directly — no profile needed.

## kubectl Access

```bash
export AWS_PROFILE=<your-profile-name>

aws eks update-kubeconfig \
  --region ap-south-1 \
  --name intangles-qa-cluster

kubectl get nodes
```

---

## Terraform Backend

State is stored in S3 with DynamoDB locking. The backend config is already set in `environments/<env>/main.tf` — no `-backend-config` flags needed.

```bash
export AWS_PROFILE=<your-profile-name>

cd environments/staging
terraform init
```

> On first clone (or after backend config changes) Terraform will prompt to reconfigure. Use `terraform init -reconfigure` if needed.

Backend details:

| Setting | Value |
|---------|-------|
| Bucket | `otel-terraform-state-setup` |
| Region | `ap-south-1` |
| DynamoDB table | `terraform-state-lock` |
| Encryption | `true` |

---

## Credentials

Two sensitive values must be provided at apply time via environment variables:

| Variable | Description |
|----------|-------------|
| `TF_VAR_elastic_password` | Elasticsearch `elastic` superuser password |
| `TF_VAR_kibana_encryption_key` | Kibana saved-objects encryption key (exactly 32 chars) |
| `TF_VAR_dash0_auth_token` | Dash0 bearer token for trace export (`Bearer <token>`) |

```bash
export TF_VAR_elastic_password='<password>'
export TF_VAR_kibana_encryption_key='<32-char-key>'
export TF_VAR_dash0_auth_token='Bearer <token>'
```

See `environments/staging/.tf_apply.sh.example` for a ready-to-copy local script template.

**Never commit these values. They must not appear in any tracked file.**

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
export AWS_PROFILE=<your-profile-name>
cd environments/staging

# Copy the example script and fill in real values
cp .tf_apply.sh.example .tf_apply.sh
# Edit .tf_apply.sh — it is git-ignored and never committed

bash .tf_apply.sh
```

Or inline:

```bash
TF_VAR_elastic_password='<password>' \
TF_VAR_kibana_encryption_key='<32-char-key>' \
TF_VAR_dash0_auth_token='Bearer <token>' \
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
