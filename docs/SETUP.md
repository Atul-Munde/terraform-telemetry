# Setup Guide - Production Configuration

## Summary of Configuration

Your OpenTelemetry Collector & Jaeger stack has been configured with:

### AWS S3 Remote State Backend
- **S3 Bucket**: `otel-terraform-state-setup`
- **Region**: `ap-south-1` (Mumbai)
- **DynamoDB Table**: `terraform-state-lock`
- **Encryption**: Enabled

### Kubernetes Configuration
- **Namespace**: `telemetry`
- **Node Selector**: `telemetry=true`
- **Toleration**: `telemetry=true:NoSchedule`
- **Storage Class**: `gp3` (AWS EBS)

---

## Pre-Deployment Steps

### 1. Create S3 Backend Infrastructure

#### Option A: Using AWS CLI

```bash
# Set your AWS region
export AWS_REGION=ap-south-1

# Create S3 bucket for Terraform state
aws s3api create-bucket \
  --bucket otel-terraform-state-setup \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1

# Enable versioning (recommended for state recovery)
aws s3api put-bucket-versioning \
  --bucket otel-terraform-state-setup \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket otel-terraform-state-setup \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access (security best practice)
aws s3api put-public-access-block \
  --bucket otel-terraform-state-setup \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-south-1
```

#### Option B: Using Terraform Bootstrap

Create a `bootstrap/main.tf`:

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "otel-terraform-state-setup"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "Terraform State Bucket"
    Purpose     = "OpenTelemetry Stack"
    Environment = "all"
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

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "Terraform State Lock Table"
    Purpose     = "OpenTelemetry Stack"
    Environment = "all"
  }
}

output "s3_bucket_name" {
  value = aws_s3_bucket.terraform_state.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.terraform_locks.id
}
```

Then run:
```bash
cd bootstrap
terraform init
terraform apply
```

### 2. Configure AWS Credentials

Ensure your AWS credentials are configured:

```bash
# Option 1: Environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="ap-south-1"

# Option 2: AWS CLI configuration
aws configure
# Enter your credentials when prompted

# Option 3: Use IAM role (recommended for EC2/EKS)
# Terraform will automatically use the instance IAM role
```

### 3. Prepare Kubernetes Nodes

Your nodes need to be labeled and tainted for the telemetry workloads.

#### Label Nodes

```bash
# List all nodes
kubectl get nodes

# Label specific nodes for telemetry
kubectl label nodes <node-name-1> telemetry=true
kubectl label nodes <node-name-2> telemetry=true
kubectl label nodes <node-name-3> telemetry=true

# Or label all nodes in a node group (if using EKS)
kubectl label nodes -l node.kubernetes.io/instance-type=m5.large telemetry=true

# Verify labels
kubectl get nodes -L telemetry
```

#### Taint Nodes

```bash
# Taint nodes to dedicate them for telemetry only
kubectl taint nodes <node-name-1> telemetry=true:NoSchedule
kubectl taint nodes <node-name-2> telemetry=true:NoSchedule
kubectl taint nodes <node-name-3> telemetry=true:NoSchedule

# Verify taints
kubectl describe node <node-name-1> | grep -A 5 Taints
```

**Note**: The `NoSchedule` taint ensures that only pods with the matching toleration (our telemetry stack) can be scheduled on these nodes.

#### Alternative: Use Node Groups

If using managed Kubernetes (EKS, GKE, AKS):

**AWS EKS - Create dedicated node group:**
```bash
eksctl create nodegroup \
  --cluster my-cluster \
  --name telemetry-nodes \
  --node-type m5.large \
  --nodes 3 \
  --nodes-min 3 \
  --nodes-max 6 \
  --node-labels telemetry=true \
  --node-taints telemetry=true:NoSchedule
```

### 4. Verify Storage Class

Ensure the `gp3` storage class exists in your cluster:

```bash
# Check available storage classes
kubectl get storageclass

# If gp3 doesn't exist, create it (for AWS EKS)
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
```

### 5. Verify Namespace

The namespace `telemetry` will be created automatically by Terraform, but you can verify:

```bash
# Check if namespace exists
kubectl get namespace telemetry

# If you want to pre-create it with additional labels
kubectl create namespace telemetry --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace telemetry monitoring=enabled
```

---

## Deployment Steps

### 1. Initialize Terraform (Dev Environment)

```bash
cd /Users/atulmunde/otel_terrform/environments/dev
terraform init
```

You should see:
```
Initializing the backend...

Successfully configured the backend "s3"!
```

### 2. Verify Configuration

```bash
# Review the plan
terraform plan

# Check what will be created
# Should show: namespace, deployments, statefulsets, services, etc.
```

### 3. Deploy

```bash
terraform apply
```

Type `yes` when prompted.

### 4. Verify Deployment

```bash
# Check all resources
kubectl get all -n telemetry

# Verify pods are running on correct nodes
kubectl get pods -n telemetry -o wide

# Check node selector worked
kubectl get pod -n telemetry -l app=otel-collector -o jsonpath='{.items[0].spec.nodeSelector}'

# Check tolerations
kubectl get pod -n telemetry -l app=otel-collector -o jsonpath='{.items[0].spec.tolerations}'

# Check PVCs using gp3
kubectl get pvc -n telemetry -o jsonpath='{.items[*].spec.storageClassName}'
```

---

## State Management

### View Remote State

```bash
# List state in S3
aws s3 ls s3://otel-terraform-state-setup/k8s-otel-jaeger/ --recursive

# Expected files:
# k8s-otel-jaeger/dev/terraform.tfstate
# k8s-otel-jaeger/staging/terraform.tfstate
# k8s-otel-jaeger/production/terraform.tfstate
```

### State Locking

When you run `terraform apply`, Terraform automatically:
1. Acquires a lock in DynamoDB
2. Prevents concurrent modifications
3. Releases the lock when done

Check locks:
```bash
aws dynamodb scan --table-name terraform-state-lock --region ap-south-1
```

### Backup and Recovery

S3 versioning is enabled, so you can recover previous state versions:

```bash
# List all versions
aws s3api list-object-versions \
  --bucket otel-terraform-state-setup \
  --prefix k8s-otel-jaeger/dev/

# Restore a previous version if needed
aws s3api get-object \
  --bucket otel-terraform-state-setup \
  --key k8s-otel-jaeger/dev/terraform.tfstate \
  --version-id <version-id> \
  terraform.tfstate.restored
```

---

## Configuration Summary

### Environment-Specific State Keys

| Environment | State Key |
|-------------|-----------|
| Dev | `k8s-otel-jaeger/dev/terraform.tfstate` |
| Staging | `k8s-otel-jaeger/staging/terraform.tfstate` |
| Production | `k8s-otel-jaeger/production/terraform.tfstate` |

### Node Requirements

Each environment needs dedicated nodes:

| Environment | Min Nodes | Recommended Instance Type (AWS) |
|-------------|-----------|----------------------------------|
| Dev | 2 | t3.medium or m5.large |
| Staging | 3 | m5.large |
| Production | 5+ | m5.xlarge or c5.xlarge |

### Storage Requirements

| Component | Storage | StorageClass |
|-----------|---------|--------------|
| Elasticsearch (Dev) | 30Gi | gp3 |
| Elasticsearch (Staging) | 75Gi | gp3 |
| Elasticsearch (Production) | 200Gi | gp3 |

---

## Troubleshooting

### Pod Pending Due to Node Selector

```bash
# Check why pod is pending
kubectl describe pod <pod-name> -n telemetry

# Common issue: No nodes with matching labels
# Solution: Label your nodes
kubectl label nodes <node-name> telemetry=true
```

### Pod Pending Due to Taint

```bash
# If you see: "node(s) had taint that the pod didn't tolerate"
# Verify the toleration is in the pod spec
kubectl get pod <pod-name> -n telemetry -o yaml | grep -A 5 tolerations

# The tolerations should be automatically added by Terraform
```

### S3 Backend Access Denied

```bash
# Verify AWS credentials
aws sts get-caller-identity

# Check S3 bucket access
aws s3 ls s3://otel-terraform-state-setup/

# Ensure IAM permissions include:
# - s3:ListBucket
# - s3:GetObject
# - s3:PutObject
# - dynamodb:PutItem
# - dynamodb:GetItem
# - dynamodb:DeleteItem
```

### PVC Pending

```bash
# Check PVC status
kubectl get pvc -n telemetry

# Verify storage class exists
kubectl get storageclass gp3

# Check PVC events
kubectl describe pvc <pvc-name> -n telemetry
```

---

## Next Steps

1. ✅ Create S3 bucket and DynamoDB table
2. ✅ Configure AWS credentials
3. ✅ Label and taint Kubernetes nodes
4. ✅ Verify gp3 storage class exists
5. ✅ Deploy to dev environment
6. ✅ Test with sample traces
7. ✅ Deploy to staging
8. ✅ Deploy to production

## Security Recommendations

- [ ] Enable S3 bucket logging
- [ ] Set up S3 lifecycle policies for old state versions
- [ ] Use IAM roles instead of access keys
- [ ] Enable CloudTrail for S3 bucket access logs
- [ ] Restrict S3 bucket access with IAM policies
- [ ] Enable MFA delete on S3 bucket
- [ ] Regularly rotate AWS credentials
- [ ] Use separate AWS accounts for different environments

---

**Ready to deploy!** 🚀
