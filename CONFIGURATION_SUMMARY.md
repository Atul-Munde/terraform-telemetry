# Configuration Summary

## ✅ What's Been Configured

### 1. AWS S3 Remote State Backend

All Terraform state is now stored remotely in AWS S3 with state locking.

**Configuration:**
- **S3 Bucket**: `otel-terraform-state-setup`
- **AWS Region**: `ap-south-1` (Mumbai)
- **DynamoDB Table**: `terraform-state-lock` (for state locking)
- **Encryption**: Enabled (AES256)

**State Keys by Environment:**
- Dev: `k8s-otel-jaeger/dev/terraform.tfstate`
- Staging: `k8s-otel-jaeger/staging/terraform.tfstate`
- Production: `k8s-otel-jaeger/production/terraform.tfstate`

### 2. Kubernetes Configuration

**Namespace:**
- Changed from `telemetry` to `telemetry`

**Node Placement:**
- **Node Selector**: `telemetry=true`
- **Toleration**: `telemetry=true:NoSchedule`
  - This ensures pods only run on dedicated telemetry nodes
  - Other workloads won't be scheduled on telemetry nodes

**Storage:**
- **StorageClass**: `gp3` (AWS EBS GP3 volumes)
- Applied to Elasticsearch PersistentVolumeClaims
- GP3 provides better performance and cost efficiency

### 3. Deployment Architecture (Production-Grade)

**Components:**
- ✅ **OpenTelemetry Collector**: Native Kubernetes resources
- ✅ **Jaeger**: Helm chart (jaegertracing/jaeger)
- ✅ **Elasticsearch**: Helm chart (elastic/elasticsearch)

This Helm-based approach for data storage components provides production-grade defaults, easier upgrades, and better maintainability while giving full control over OTel Collector configuration.

---

## 📋 Before You Deploy Checklist

### AWS Prerequisites

- [ ] **Create S3 Bucket**
  ```bash
  aws s3api create-bucket --bucket otel-terraform-state-setup \
    --region ap-south-1 \
    --create-bucket-configuration LocationConstraint=ap-south-1
  ```

- [ ] **Enable Versioning** (for state recovery)
  ```bash
  aws s3api put-bucket-versioning \
    --bucket otel-terraform-state-setup \
    --versioning-configuration Status=Enabled
  ```

- [ ] **Create DynamoDB Table** (for locking)
  ```bash
  aws dynamodb create-table --table-name terraform-state-lock \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST --region ap-south-1
  ```

- [ ] **Configure AWS Credentials**
  ```bash
  export AWS_ACCESS_KEY_ID="your-key"
  export AWS_SECRET_ACCESS_KEY="your-secret"
  export AWS_DEFAULT_REGION="ap-south-1"
  # OR use: aws configure
  ```

### Kubernetes Prerequisites

- [ ] **Label Nodes** for telemetry workloads
  ```bash
  # Label at least 3 nodes for production, 2 for staging/dev
  kubectl label nodes <node-1> telemetry=true
  kubectl label nodes <node-2> telemetry=true
  kubectl label nodes <node-3> telemetry=true
  
  # Verify
  kubectl get nodes -L telemetry
  ```

- [ ] **Taint Nodes** to dedicate them
  ```bash
  # This prevents other workloads from running on these nodes
  kubectl taint nodes <node-1> telemetry=true:NoSchedule
  kubectl taint nodes <node-2> telemetry=true:NoSchedule
  kubectl taint nodes <node-3> telemetry=true:NoSchedule
  
  # Verify
  kubectl describe node <node-1> | grep -A 3 Taints
  ```

- [ ] **Verify Storage Class** exists
  ```bash
  kubectl get storageclass gp3
  
  # If not exists, create it (AWS EKS example)
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

---

## 🚀 Deployment Steps

### Development Environment

```bash
cd /Users/atulmunde/otel_terrform/environments/dev

# Initialize (downloads providers, configures S3 backend)
terraform init

# Review what will be created
terraform plan

# Deploy
terraform apply

# Verify
kubectl get pods -n telemetry
make validate  # or: /Users/atulmunde/otel_terrform/scripts/validate.sh
```

### Staging Environment

```bash
cd /Users/atulmunde/otel_terrform/environments/staging
terraform init
terraform plan
terraform apply
```

### Production Environment

```bash
cd /Users/atulmunde/otel_terrform/environments/production
terraform init
terraform plan
terraform apply  # Requires confirmation
```

---

## 🔍 Verification Commands

### Check Pods are on Correct Nodes

```bash
# Verify node placement
kubectl get pods -n telemetry -o wide

# Expected: All pods should be on nodes labeled telemetry=true
kubectl get nodes -l telemetry=true
```

### Verify Tolerations

```bash
# Check if tolerations are applied
kubectl get pod -n telemetry -l app=otel-collector \
  -o jsonpath='{.items[0].spec.tolerations}' | jq
```

### Verify Storage Class

```bash
# Check PVCs are using gp3
kubectl get pvc -n telemetry \
  -o custom-columns=NAME:.metadata.name,STORAGECLASS:.spec.storageClassName

# Expected: All should show 'gp3'
```

### Check Remote State

```bash
# Verify state is in S3
aws s3 ls s3://otel-terraform-state-setup/k8s-otel-jaeger/ --recursive

# Check DynamoDB lock table
aws dynamodb scan --table-name terraform-state-lock --region ap-south-1
```

---

## 📊 Resource Distribution

### By Environment

| Environment | OTel Pods | Jaeger Pods | ES Pods | Total | Min Nodes |
|-------------|-----------|-------------|---------|-------|-----------|
| **Dev** | 2 | 2 | 1 | 5 | 2 |
| **Staging** | 2-8 (HPA) | 4 | 2 | 8-14 | 3 |
| **Production** | 3-15 (HPA) | 6 | 3 | 12-24 | 5 |

### Node Requirements

**Development:**
- 2 nodes labeled `telemetry=true`
- Instance type: `t3.medium` or `m5.large`
- 2 vCPU, 4GB RAM minimum per node

**Staging:**
- 3 nodes labeled `telemetry=true`
- Instance type: `m5.large`
- 2 vCPU, 8GB RAM per node

**Production:**
- 5+ nodes labeled `telemetry=true`
- Instance type: `m5.xlarge` or `c5.xlarge`
- 4 vCPU, 16GB RAM per node

---

## 🎯 Endpoints After Deployment

### From Inside Cluster

Applications should send traces to:
- **OTLP gRPC**: `otel-collector.telemetry.svc.cluster.local:4317`
- **OTLP HTTP**: `otel-collector.telemetry.svc.cluster.local:4318`

### From Developer Machine

```bash
# Jaeger UI
kubectl port-forward -n telemetry svc/jaeger-query 16686:16686
# Open: http://localhost:16686

# Elasticsearch
kubectl port-forward -n telemetry svc/elasticsearch 9200:9200
# Open: http://localhost:9200

# OTel Collector metrics
kubectl port-forward -n telemetry svc/otel-collector 8888:8888
# Open: http://localhost:8888/metrics
```

---

## 📖 Documentation

Full documentation available in `/Users/atulmunde/otel_terrform/docs/`:

1. **[SETUP.md](docs/SETUP.md)** - Complete setup guide with AWS and K8s prerequisites
2. **[TRADEOFFS.md](docs/TRADEOFFS.md)** - Detailed analysis of Helm vs Native Kubernetes
3. **[DEPLOYMENT.md](docs/DEPLOYMENT.md)** - Step-by-step deployment instructions
4. **[APPLICATION_INTEGRATION.md](docs/APPLICATION_INTEGRATION.md)** - How to integrate apps (Go, Python, Node.js, Java)
5. **[QUICKSTART.md](docs/QUICKSTART.md)** - Quick 5-minute setup
6. **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Architecture and design decisions

---

## ❓ FAQ

### Q: Why S3 in ap-south-1?
**A:** Based on your input. Change region in `backend.tf` and environment main.tf files if needed.

### Q: Can I use a different namespace?
**A:** Yes, change `namespace = "telemetry"` in `variables.tf` and environment tfvars files.

### Q: What if I don't want dedicated nodes?
**A:** Remove or comment out node_selector and tolerations in `variables.tf`. Set:
```hcl
node_selector = {}
tolerations = []
```

### Q: Can I use a different storage class?
**A:** Yes, change `elasticsearch_storage_class = "gp3"` to your preferred storage class.

### Q: Why not use Helm for everything?
**A:** See [TRADEOFFS.md](docs/TRADEOFFS.md) for detailed analysis. TL;DR: Better control and cost efficiency.

### Q: How do I migrate existing state to S3?
**A:** Run `terraform init -migrate-state` in each environment directory.

---

## 🛠 Troubleshooting

### Pods Stuck in Pending

**Issue:** Pods show "0/3 nodes are available: node(s) didn't match Pod's node affinity/selector"

**Solution:**
```bash
# Check if nodes are labeled
kubectl get nodes -L telemetry

# If not, label them
kubectl label nodes <node-name> telemetry=true
```

### S3 Access Denied

**Issue:** "Error: error configuring S3 Backend: AccessDenied"

**Solution:**
```bash
# Verify AWS credentials
aws sts get-caller-identity

# Test S3 access
aws s3 ls s3://otel-terraform-state-setup/

# Ensure IAM permissions include:
# - s3:ListBucket, s3:GetObject, s3:PutObject
# - dynamodb:PutItem, dynamodb:GetItem, dynamodb:DeleteItem
```

### PVC Pending

**Issue:** PersistentVolumeClaim stuck in "Pending"

**Solution:**
```bash
# Check if storage class exists
kubectl get storageclass gp3

# Describe PVC for details
kubectl describe pvc -n telemetry

# Verify nodes have available storage
kubectl get nodes -o custom-columns=NAME:.metadata.name,STORAGE:.status.allocatable.storage
```

---

## 🎉 You're Ready!

Your production-grade OpenTelemetry Collector and Jaeger stack is configured with:
- ✅ Remote state management (S3 + DynamoDB)
- ✅ Dedicated Kubernetes nodes
- ✅ High-performance storage (GP3)
- ✅ Production-ready architecture
- ✅ Multi-environment support

**Next step:** Follow the checklist above and deploy! 🚀

For questions, see documentation in `docs/` or review the trade-offs analysis in [docs/TRADEOFFS.md](docs/TRADEOFFS.md).
