# Terraform Directory Structure & Data Flow

Complete guide to understanding the Terraform project structure, file organization, and how configurations are imported and applied.

---

## 📁 Complete Directory Structure

```
/Users/atulmunde/otel_terrform/
│
├── 📄 Root Module Files (Base Configuration)
│   ├── main.tf                      # Orchestrates all module calls
│   ├── variables.tf                 # Input variable declarations
│   ├── outputs.tf                   # Output value definitions
│   ├── versions.tf                  # Terraform & provider versions
│   ├── backend.tf                   # Remote state configuration
│   └── terraform.tfvars.example     # Example variable values
│
├── 📦 modules/                      # Reusable Terraform modules
│   │
│   ├── namespace/                   # Kubernetes namespace module
│   │   ├── main.tf                  # Namespace resource definition
│   │   ├── variables.tf             # Module input variables
│   │   └── outputs.tf               # Module outputs
│   │
│   ├── elasticsearch/               # Elasticsearch Helm deployment
│   │   ├── main.tf                  # Helm release resource
│   │   ├── variables.tf             # ES configuration variables
│   │   └── outputs.tf               # ES service endpoints
│   │
│   ├── jaeger/                      # Jaeger Helm deployment
│   │   ├── main.tf                  # Helm release for Jaeger
│   │   ├── variables.tf             # Jaeger configuration
│   │   └── outputs.tf               # Jaeger endpoints
│   │
│   └── otel-collector/              # OpenTelemetry Collector
│       ├── main.tf                  # Module entry point
│       ├── variables.tf             # OTel configuration vars
│       ├── outputs.tf               # Service endpoints
│       ├── configmap.tf             # OTel YAML configuration
│       ├── deployment.tf            # K8s Deployment + RBAC
│       ├── service.tf               # Kubernetes Service
│       └── hpa.tf                   # HorizontalPodAutoscaler
│
├── 🌍 environments/                 # Environment-specific configs
│   │
│   ├── dev/                         # Development environment
│   │   ├── main.tf                  # Imports root module
│   │   └── terraform.tfvars         # Dev-specific values
│   │
│   ├── staging/                     # Staging environment
│   │   ├── main.tf                  # Imports root module
│   │   ├── terraform.tfvars         # Staging-specific values
│   │   ├── deploy.sh                # Deployment script
│   │   ├── test-tracing.sh          # E2E testing script
│   │   ├── terraform-plan-output.json
│   │   └── terraform-plan-output.txt
│   │
│   └── production/                  # Production environment
│       ├── main.tf                  # Imports root module
│       └── terraform.tfvars         # Production-specific values
│
├── 📜 scripts/                      # Helper automation scripts
│   ├── deploy.sh                    # Full deployment automation
│   ├── cleanup.sh                   # Resource teardown
│   └── validate.sh                  # Health check validation
│
├── 📚 docs/                         # Documentation
│   ├── QUICKSTART.md                # Quick start guide
│   ├── DEPLOYMENT.md                # Detailed deployment steps
│   ├── ARCHITECTURE.md              # System architecture
│   ├── TRADEOFFS.md                 # Design decisions
│   ├── SETUP.md                     # Initial setup guide
│   ├── APPLICATION_INTEGRATION.md   # App integration guide
│   └── TERRAFORM_STRUCTURE.md       # This file
│
├── 🛠️ Configuration & Build Files
│   ├── Makefile                     # Convenient make commands
│   ├── .gitignore                   # Git ignore patterns
│   ├── .terraform.lock.hcl          # Provider dependency lock
│   ├── CONFIGURATION_SUMMARY.md     # Configuration summary
│   └── README.md                    # Main project README
│
└── 🔒 Terraform Working Directory
    └── .terraform/                  # Terraform cache directory
        └── providers/               # Downloaded provider plugins
```

---

## 📋 File-by-File Breakdown

### Root Module Files

#### **main.tf**
**Purpose:** Orchestrates the entire infrastructure deployment

**Structure:**
```terraform
# 1. Provider Configuration
provider "kubernetes" { }
provider "helm" { }

# 2. Local Variables
locals {
  common_labels = { environment, managed-by, project }
}

# 3. Module Calls (in dependency order)
module "namespace" {
  source = "./modules/namespace"
  # variables passed here
}

module "elasticsearch" {
  source = "./modules/elasticsearch"
  depends_on = [module.namespace]
  # variables passed here
}

module "jaeger" {
  source = "./modules/jaeger"
  depends_on = [module.namespace, module.elasticsearch]
  # variables passed here
}

module "otel_collector" {
  source = "./modules/otel-collector"
  depends_on = [module.namespace, module.jaeger]
  # variables passed here
}
```

**Key Features:**
- Defines provider configurations
- Creates local variables for common labels
- Calls all modules in correct dependency order
- Passes variables from root level to modules

---

#### **variables.tf**
**Purpose:** Declares all input variables with validation

**Structure:**
```terraform
variable "environment" {
  description = "Environment name (dev/staging/production)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "telemetry"
}

variable "elasticsearch_replicas" {
  description = "Number of Elasticsearch nodes"
  type        = number
  default     = 2
  validation {
    condition     = var.elasticsearch_replicas >= 1
    error_message = "Must have at least 1 replica"
  }
}

# ... 20+ more variables
```

**Variable Categories:**
1. **Environment Settings:** environment, namespace, labels
2. **Elasticsearch Config:** replicas, storage_size, storage_class, memory, heap_size
3. **Jaeger Config:** collector_replicas, query_replicas, chart_version
4. **OTel Collector:** replicas, image, resources, hpa settings
5. **Common Settings:** node_selector, tolerations, data_retention_days

---

#### **outputs.tf**
**Purpose:** Exports important values after deployment

**Structure:**
```terraform
output "namespace" {
  description = "Kubernetes namespace where stack is deployed"
  value       = module.namespace.namespace
}

output "otel_collector_endpoint_grpc" {
  description = "OTel Collector gRPC endpoint"
  value       = "otel-collector.${var.namespace}.svc.cluster.local:4317"
}

output "jaeger_ui_url" {
  description = "Command to access Jaeger UI"
  value       = "kubectl port-forward -n ${var.namespace} svc/jaeger-query 16686:16686"
}

# ... more outputs
```

**Output Types:**
- Service endpoints (OTel, Jaeger, Elasticsearch)
- Access commands (kubectl port-forward)
- Configuration values
- Resource names

---

#### **versions.tf**
**Purpose:** Version constraints for Terraform and providers

**Content:**
```terraform
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}
```

**Why Important:**
- Ensures consistent behavior across team
- Prevents breaking changes from provider updates
- Documents minimum Terraform version needed

---

#### **backend.tf**
**Purpose:** Configures remote state storage

**Content:**
```terraform
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
```

**State Storage:**
- **Location:** AWS S3 bucket (ap-south-1 region)
- **Encryption:** Enabled (server-side)
- **Locking:** DynamoDB table prevents concurrent modifications
- **Profile:** Uses AWS profile `mum-test` for authentication

**State Keys by Environment:**
- Root: `k8s-otel-jaeger/terraform.tfstate` (not used directly)
- Dev: `k8s-otel-jaeger/dev/terraform.tfstate`
- Staging: `k8s-otel-jaeger/staging/terraform.tfstate`
- Production: `k8s-otel-jaeger/production/terraform.tfstate`

---

#### **terraform.tfvars.example**
**Purpose:** Template showing how to configure variables

**Content:**
```hcl
environment = "staging"
namespace   = "telemetry"

elasticsearch_replicas     = 2
elasticsearch_storage_size = "75Gi"
elasticsearch_storage_class = "gp3"

jaeger_collector_replicas = 2
jaeger_query_replicas     = 2

otel_collector_replicas = 1

# ... more examples
```

**Usage:**
```bash
# Copy and customize for each environment
cp terraform.tfvars.example environments/staging/terraform.tfvars
```

---

## 📦 Modules Deep Dive

### Module: namespace/

**Files:**
```
namespace/
├── main.tf       # Creates/references K8s namespace
├── variables.tf  # Input: namespace, labels, create_namespace
└── outputs.tf    # Output: namespace name
```

**main.tf:**
```terraform
resource "kubernetes_namespace" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name   = var.namespace
    labels = var.labels
  }
}

data "kubernetes_namespace" "existing" {
  count = var.create_namespace ? 0 : 1
  metadata {
    name = var.namespace
  }
}
```

**Purpose:**
- Creates new namespace OR references existing one
- Applies common labels
- Foundation for all other resources

---

### Module: elasticsearch/

**Files:**
```
elasticsearch/
├── main.tf       # Helm release for Elasticsearch
├── variables.tf  # Replicas, storage, memory, etc.
└── outputs.tf    # Service name, connection URL
```

**main.tf Structure:**
```terraform
resource "helm_release" "elasticsearch" {
  name       = "elasticsearch"
  repository = "https://helm.elastic.co"
  chart      = "elasticsearch"
  version    = "8.5.1"
  namespace  = var.namespace

  values = [yamlencode({
    replicas = var.replicas
    
    volumeClaimTemplate = {
      resources = {
        requests = {
          storage = var.storage_size
        }
      }
    }
    
    resources = {
      limits = {
        memory = var.memory_limit
      }
    }
    
    esConfig = {
      "elasticsearch.yml" = {
        "xpack.security.enabled" = false
      }
    }
    
    # ... more configuration
  })]
}
```

**Key Features:**
- Uses official Elastic Helm chart
- Dynamic heap size calculation (50% of memory)
- PersistentVolumeClaims with gp3 storage
- Proper security settings for internal use

**Outputs:**
```terraform
output "service_name" {
  value = "elasticsearch-master"
}

output "connection_url" {
  value = "http://elasticsearch-master.${var.namespace}.svc.cluster.local:9200"
}
```

---

### Module: jaeger/

**Files:**
```
jaeger/
├── main.tf       # Helm release for Jaeger
├── variables.tf  # Collector/Query config, storage settings
└── outputs.tf    # Collector/Query endpoints
```

**main.tf Structure:**
```terraform
resource "helm_release" "jaeger" {
  name       = "jaeger"
  repository = "https://jaegertracing.github.io/helm-charts"
  chart      = "jaeger"
  version    = "2.0.0"
  namespace  = var.namespace

  values = [yamlencode({
    storage = {
      type = "elasticsearch"
      elasticsearch = {
        scheme = "http"
        host   = var.elasticsearch_host
        port   = var.elasticsearch_port
      }
    }
    
    collector = {
      enabled      = true
      replicaCount = var.collector_replicas
      service = {
        otlp = {
          grpc = { port = 4317 }
          http = { port = 4318 }
        }
      }
    }
    
    query = {
      enabled      = true
      replicaCount = var.query_replicas
    }
  })]
}
```

**Key Configuration:**
- **Storage Backend:** Points to Elasticsearch service
- **Collector:** Receives traces via OTLP (4317/4318)
- **Query UI:** Serves web interface (16686)
- **Components:** All-in-one disabled, separate services

**Outputs:**
```terraform
output "collector_endpoint" {
  value = "jaeger-collector.${var.namespace}.svc.cluster.local:4317"
}

output "query_ui_service" {
  value = "jaeger-query.${var.namespace}.svc.cluster.local:16686"
}
```

---

### Module: otel-collector/

**Files:**
```
otel-collector/
├── main.tf         # Module entry point
├── variables.tf    # Configuration variables
├── outputs.tf      # Service endpoints
├── configmap.tf    # OTel Collector YAML config
├── deployment.tf   # Deployment + RBAC resources
├── service.tf      # Kubernetes Service
└── hpa.tf          # HorizontalPodAutoscaler
```

#### **configmap.tf**
**Purpose:** Defines OTel Collector configuration

```terraform
resource "kubernetes_config_map" "otel_collector" {
  metadata {
    name      = "otel-collector-config"
    namespace = var.namespace
  }

  data = {
    "otel-collector-config.yaml" = yamlencode({
      receivers = {
        otlp = {
          protocols = {
            grpc = { endpoint = "0.0.0.0:4317" }
            http = { endpoint = "0.0.0.0:4318" }
          }
        }
      }
      
      processors = {
        memory_limiter = {
          check_interval = "1s"
          limit_mib      = 512
        }
        batch = {
          timeout       = "10s"
          send_batch_size = 1024
        }
        k8sattributes = {
          extract = {
            metadata = ["k8s.namespace.name", "k8s.pod.name"]
          }
        }
      }
      
      exporters = {
        otlp = {
          endpoint = var.jaeger_endpoint
          tls = { insecure = true }
        }
        logging = {
          loglevel = "info"
        }
      }
      
      service = {
        pipelines = {
          traces = {
            receivers  = ["otlp"]
            processors = ["memory_limiter", "k8sattributes", "batch"]
            exporters  = ["otlp", "logging"]
          }
        }
      }
    })
  }
}
```

**Configuration Sections:**
1. **Receivers:** Accept OTLP traces (gRPC/HTTP)
2. **Processors:** Memory limiting, batching, K8s attributes
3. **Exporters:** Send to Jaeger (OTLP) + logging
4. **Pipelines:** Connect receivers → processors → exporters

#### **deployment.tf**
**Purpose:** K8s Deployment and RBAC

```terraform
resource "kubernetes_service_account" "otel_collector" {
  metadata {
    name      = "otel-collector"
    namespace = var.namespace
  }
}

resource "kubernetes_cluster_role" "otel_collector" {
  metadata {
    name = "otel-collector"
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "namespaces"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_deployment" "otel_collector" {
  metadata {
    name      = "otel-collector"
    namespace = var.namespace
  }
  
  spec {
    replicas = var.replicas
    
    template {
      spec {
        service_account_name = kubernetes_service_account.otel_collector.metadata[0].name
        
        container {
          name  = "otel-collector"
          image = var.image
          
          volume_mount {
            name       = "config"
            mount_path = "/etc/otel-collector-config.yaml"
            sub_path   = "otel-collector-config.yaml"
          }
          
          # ... ports, probes, resources
        }
        
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.otel_collector.metadata[0].name
          }
        }
      }
    }
  }
}
```

**Key Features:**
- ServiceAccount with K8s API access (for k8sattributes processor)
- ConfigMap mounted as volume
- Health probes on port 13133
- Resource requests and limits

#### **service.tf**
**Purpose:** Expose OTel Collector ports

```terraform
resource "kubernetes_service" "otel_collector" {
  metadata {
    name      = "otel-collector"
    namespace = var.namespace
  }
  
  spec {
    type = "ClusterIP"
    
    selector = {
      app = "otel-collector"
    }
    
    port {
      name        = "otlp-grpc"
      port        = 4317
      target_port = 4317
      protocol    = "TCP"
    }
    
    port {
      name        = "otlp-http"
      port        = 4318
      target_port = 4318
      protocol    = "TCP"
    }
    
    port {
      name        = "metrics"
      port        = 8888
      target_port = 8888
    }
  }
}
```

**Exposed Ports:**
- **4317:** OTLP gRPC (primary trace ingestion)
- **4318:** OTLP HTTP (alternative ingestion)
- **8888:** Prometheus metrics
- **13133:** Health check endpoint

#### **hpa.tf**
**Purpose:** Auto-scaling based on resource usage

```terraform
resource "kubernetes_horizontal_pod_autoscaler_v2" "otel_collector" {
  count = var.hpa_enabled ? 1 : 0
  
  metadata {
    name      = "otel-collector-hpa"
    namespace = var.namespace
  }
  
  spec {
    min_replicas = var.hpa_min_replicas
    max_replicas = var.hpa_max_replicas
    
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.hpa_target_cpu
        }
      }
    }
    
    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = var.hpa_target_memory
        }
      }
    }
  }
}
```

**Scaling Rules:**
- Scale based on CPU and memory utilization
- Default: 1-5 replicas
- Target: 70% CPU, 80% memory

---

## 🌍 Environments Deep Dive

### How Environments Work

Each environment directory (`dev/`, `staging/`, `production/`) contains:

```
staging/
├── main.tf              # Imports root module
├── terraform.tfvars     # Environment-specific values
└── [optional scripts]   # Deployment helpers
```

### environments/staging/main.tf

**Structure:**
```terraform
# 1. Terraform Configuration Block
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.25" }
    helm       = { source = "hashicorp/helm", version = "~> 2.12" }
  }
  
  # Environment-specific backend
  backend "s3" {
    bucket = "otel-terraform-state-setup"
    key    = "k8s-otel-jaeger/staging/terraform.tfstate"  # Unique per env
    region = "ap-south-1"
    dynamodb_table = "terraform-state-lock"
    encrypt = true
    profile = "mum-test"
  }
}

# 2. Provider Configuration
provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# 3. Import Root Module
module "telemetry" {
  source = "../.."  # Points to root directory
  
  # Pass all variables
  environment = "staging"
  namespace   = "telemetry"
  
  elasticsearch_replicas      = 2
  elasticsearch_storage_size  = "75Gi"
  elasticsearch_storage_class = "gp3"
  
  jaeger_collector_replicas = 2
  jaeger_query_replicas     = 2
  
  otel_collector_replicas = 1
  
  # ... all other variables
}

# 4. Environment-specific Outputs
output "otel_endpoint" {
  value = module.telemetry.otel_collector_endpoint_grpc
}

output "jaeger_ui_access" {
  value = module.telemetry.jaeger_query_ui_access_command
}
```

### environments/staging/terraform.tfvars

**Purpose:** Override default values for staging

**Content:**
```hcl
# Environment
environment = "staging"
namespace   = "telemetry"

# Elasticsearch
elasticsearch_replicas      = 2
elasticsearch_storage_size  = "75Gi"
elasticsearch_storage_class = "gp3"
elasticsearch_memory_limit  = "4Gi"
elasticsearch_heap_size     = "2048m"

# Jaeger
jaeger_collector_replicas = 2
jaeger_query_replicas     = 2
jaeger_chart_version      = "2.0.0"

# OTel Collector
otel_collector_replicas = 1
otel_collector_image    = "otel/opentelemetry-collector-contrib:0.95.0"

# Common
node_selector = {
  "telemetry" = "true"
}

tolerations = [
  {
    key      = "telemetry"
    operator = "Equal"
    value    = "true"
    effect   = "NoSchedule"
  }
]

data_retention_days = 7
```

**Variable Precedence:**
1. **terraform.tfvars** (highest priority)
2. **CLI flags** (`-var="key=value"`)
3. **Environment variables** (`TF_VAR_name=value`)
4. **Default values** in variables.tf (lowest priority)

---

## 🔄 Data Flow & Import Mechanism

### Execution Flow

```
┌─────────────────────────────────────────────────────┐
│ 1. User runs: terraform apply                       │
│    in: environments/staging/                        │
└─────────────────┬───────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────┐
│ 2. Terraform reads: staging/main.tf                 │
│    - Backend config (S3 state location)            │
│    - Provider config (kubernetes, helm)             │
│    - Module import: source = "../.."               │
└─────────────────┬───────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────┐
│ 3. Terraform loads: staging/terraform.tfvars        │
│    - Reads variable values                          │
│    - Merges with defaults from ../../variables.tf  │
└─────────────────┬───────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────┐
│ 4. Terraform executes: ../../main.tf                │
│    (Root module with staging variables)            │
└─────────────────┬───────────────────────────────────┘
                  │
        ┌─────────┴─────────┬──────────┬──────────┐
        ▼                   ▼          ▼          ▼
   ┌─────────┐      ┌──────────┐  ┌────────┐  ┌──────────┐
   │ namespace│      │ elasticsearch│  │ jaeger │  │ otel-    │
   │ module  │ ───▶ │   module   │  │ module │  │ collector│
   │         │      │            │  │        │  │ module   │
   └─────────┘      └────────────┘  └────────┘  └──────────┘
        │                   │          │          │
        └───────────────────┴──────────┴──────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────┐
│ 5. Resources created in Kubernetes cluster          │
│    - Namespace: telemetry                           │
│    - Helm Release: elasticsearch                    │
│    - Helm Release: jaeger                           │
│    - Deployment: otel-collector                     │
│    - Services, ConfigMaps, RBAC, etc.              │
└─────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────┐
│ 6. State saved to S3                                │
│    s3://otel-terraform-state-setup/                 │
│       k8s-otel-jaeger/staging/terraform.tfstate     │
└─────────────────────────────────────────────────────┘
```

### Module Import Chain

**Step-by-step:**

1. **Environment layer calls root:**
   ```terraform
   # environments/staging/main.tf
   module "telemetry" {
     source = "../.."  # Relative path to root
     # Pass variables
   }
   ```

2. **Root module calls sub-modules:**
   ```terraform
   # main.tf (root)
   module "namespace" {
     source = "./modules/namespace"  # Relative to root
   }
   
   module "elasticsearch" {
     source = "./modules/elasticsearch"
   }
   ```

3. **Modules receive variables:**
   ```terraform
   # modules/elasticsearch/main.tf
   # Uses: var.replicas (passed from root)
   #       var.storage_size (passed from root)
   ```

4. **Modules return outputs:**
   ```terraform
   # modules/elasticsearch/outputs.tf
   output "service_name" {
     value = "elasticsearch-master"
   }
   
   # Root uses: module.elasticsearch.service_name
   ```

### Variable Passing Flow

```
terraform.tfvars (staging)
    replicas = 2
         │
         ▼
module "telemetry" block (staging/main.tf)
    elasticsearch_replicas = 2
         │
         ▼
Root main.tf
    module "elasticsearch" {
      replicas = var.elasticsearch_replicas  # = 2
    }
         │
         ▼
modules/elasticsearch/main.tf
    resource "helm_release" {
      values = { replicas = var.replicas }  # = 2
    }
         │
         ▼
Kubernetes Cluster
    StatefulSet with 2 replicas created
```

### Dependency Management

**Explicit Dependencies:**
```terraform
module "jaeger" {
  depends_on = [module.namespace, module.elasticsearch]
  # Won't start until namespace and ES are ready
}
```

**Implicit Dependencies:**
```terraform
module "jaeger" {
  elasticsearch_host = module.elasticsearch.service_name
  # Terraform detects dependency automatically
}
```

**Execution Order:**
1. ✅ Namespace (no dependencies)
2. ✅ Elasticsearch (depends on namespace - via implicit reference)
3. ✅ Jaeger (depends on namespace + elasticsearch - explicit)
4. ✅ OTel Collector (depends on namespace + jaeger - explicit)

---

## 🔐 State Management Details

### State File Structure

```
s3://otel-terraform-state-setup/
└── k8s-otel-jaeger/
    ├── dev/
    │   └── terraform.tfstate
    ├── staging/
    │   └── terraform.tfstate
    └── production/
        └── terraform.tfstate
```

### What's in State File?

The state file contains:
- **Resource IDs:** Kubernetes resource names, UIDs
- **Current configuration:** Replicas, storage sizes, images
- **Dependencies:** Relationship between resources
- **Outputs:** Computed values
- **Provider configuration:** Not sensitive credentials

**Example state content:**
```json
{
  "version": 4,
  "terraform_version": "1.5.0",
  "resources": [
    {
      "module": "module.telemetry.module.elasticsearch",
      "type": "helm_release",
      "name": "elasticsearch",
      "instances": [
        {
          "attributes": {
            "id": "telemetry/elasticsearch",
            "name": "elasticsearch",
            "namespace": "telemetry",
            "status": "deployed"
          }
        }
      ]
    }
  ]
}
```

### State Locking

**DynamoDB Table:** `terraform-state-lock`

**Lock Process:**
1. User runs `terraform apply` in staging
2. Terraform creates lock entry in DynamoDB
3. Lock contains: environment path, user, timestamp
4. Other users get error: "State locked"
5. After apply completes, lock released automatically

**Lock Entry:**
```json
{
  "LockID": "otel-terraform-state-setup/k8s-otel-jaeger/staging/terraform.tfstate-md5",
  "Info": {
    "ID": "abc123",
    "Operation": "OperationTypeApply",
    "Who": "user@hostname",
    "Created": "2026-02-13T10:30:00Z"
  }
}
```

---

## 🚀 Common Operations

### Deploy New Environment

```bash
# 1. Navigate to environment
cd environments/staging/

# 2. Initialize Terraform (downloads providers)
terraform init

# 3. Review what will be created
terraform plan

# 4. Apply changes
terraform apply

# 5. Save outputs
terraform output > outputs.txt
```

### Make Configuration Changes

```bash
# 1. Edit variables
vim terraform.tfvars

# Change: elasticsearch_replicas = 2 → 3

# 2. Preview changes
terraform plan

# Shows: will modify elasticsearch helm_release

# 3. Apply changes
terraform apply
```

### Update Module Code

```bash
# 1. Edit module in root
vim ../../modules/elasticsearch/main.tf

# 2. Changes affect ALL environments using that module

# 3. Test in dev first
cd environments/dev/
terraform plan
terraform apply

# 4. Then deploy to staging
cd ../staging/
terraform apply

# 5. Finally production
cd ../production/
terraform apply
```

### View Current State

```bash
# List all resources
terraform state list

# Show specific resource
terraform state show module.telemetry.module.elasticsearch.helm_release.elasticsearch

# View outputs
terraform output

# Show dependency graph
terraform graph | dot -Tpng > graph.png
```

### Destroy Environment

```bash
# Destroy everything
terraform destroy

# Destroy specific module
terraform destroy -target=module.telemetry.module.otel_collector

# Note: Dependencies prevent out-of-order destruction
```

---

## 📊 Resource Interrelationships

### Service Communication

```
┌─────────────────────────────────────────────────────┐
│ Kubernetes Cluster (telemetry namespace)            │
├─────────────────────────────────────────────────────┤
│                                                      │
│  Application Pods (any namespace)                   │
│         │                                            │
│         │ Send traces via OTLP                      │
│         ▼                                            │
│  ┌─────────────────────────┐                       │
│  │ otel-collector Service  │                       │
│  │ - Port 4317 (gRPC)     │                       │
│  │ - Port 4318 (HTTP)     │                       │
│  └──────────┬──────────────┘                       │
│             │                                         │
│             │ Forward via OTLP to:                   │
│             │ jaeger-collector:4317                  │
│             ▼                                         │
│  ┌─────────────────────────┐                       │
│  │ jaeger-collector        │                       │
│  │ - Port 4317 (OTLP)     │                       │
│  └──────────┬──────────────┘                       │
│             │                                         │
│             │ Write spans to:                        │
│             │ elasticsearch-master:9200              │
│             ▼                                         │
│  ┌─────────────────────────┐                       │
│  │ elasticsearch-master    │                       │
│  │ - Port 9200 (HTTP)     │                       │
│  │ - StatefulSet with PVCs │                       │
│  └──────────┬──────────────┘                       │
│             ▲                                         │
│             │ Query spans                            │
│             │                                         │
│  ┌──────────┴──────────────┐                       │
│  │ jaeger-query            │                       │
│  │ - Port 16686 (UI)      │                       │
│  └─────────────────────────┘                       │
│                                                      │
└─────────────────────────────────────────────────────┘
```

### DNS Names

All services accessible via Kubernetes DNS:

```
otel-collector.telemetry.svc.cluster.local:4317
jaeger-collector.telemetry.svc.cluster.local:4317
jaeger-query.telemetry.svc.cluster.local:16686
elasticsearch-master.telemetry.svc.cluster.local:9200
```

### ConfigMap References

```
OTel Collector Deployment
    └─ volumeMount: /etc/otel-collector-config.yaml
         └─ volume: configMap
              └─ name: otel-collector-config
                   └─ data["otel-collector-config.yaml"]
                        └─ Contains: receivers, processors, exporters
```

---

## 🎯 Best Practices

### 1. **Environment Isolation**
- ✅ Each environment has separate state file
- ✅ Test changes in dev before staging/production
- ✅ Use consistent naming across environments

### 2. **Variable Management**
- ✅ Define all variables in root variables.tf
- ✅ Document each variable with description
- ✅ Use validation rules for critical variables
- ✅ Keep sensitive values in terraform.tfvars (gitignored)

### 3. **Module Design**
- ✅ Modules should be self-contained
- ✅ Use clear input/output contracts
- ✅ Return useful outputs for references
- ✅ Document module purpose and usage

### 4. **State Management**
- ✅ Always use remote state (S3)
- ✅ Enable state locking (DynamoDB)
- ✅ Enable encryption for state files
- ✅ Never commit state to git

### 5. **Version Control**
- ✅ Commit all .tf files
- ✅ Gitignore: .terraform/, *.tfstate, terraform.tfvars
- ✅ Pin provider versions in versions.tf
- ✅ Use terraform.lock.hcl for reproducibility

### 6. **Workflow**
```bash
# Always:
terraform fmt       # Format code
terraform validate  # Validate syntax
terraform plan      # Preview changes
terraform apply     # Apply changes

# Review output carefully before confirming
```

---

## 📝 Summary

### Key Takeaways

1. **Modular Structure:** Reusable modules for each component
2. **Environment Separation:** Dev/Staging/Prod with isolated state
3. **Remote State:** S3 backend with DynamoDB locking
4. **Variable Hierarchy:** Root → Environment → Module
5. **Explicit Dependencies:** Ensures correct resource ordering
6. **Helm Integration:** Uses official charts for ES and Jaeger
7. **Native K8s:** Direct control over OTel Collector
8. **Production-Ready:** HA, auto-scaling, monitoring included

### Quick Reference

**To deploy staging:**
```bash
cd environments/staging/
terraform init
terraform plan
terraform apply
```

**To modify configuration:**
1. Edit `terraform.tfvars`
2. Run `terraform plan` to preview
3. Run `terraform apply` to deploy

**To update module code:**
1. Edit files in `modules/`
2. Changes propagate to all environments
3. Test in dev first, then staging, then production

**Resource naming pattern:**
- Modules: `module.telemetry.module.<component>`
- Resources: `<type>.<name>` (e.g., `helm_release.elasticsearch`)
- Services: `<component>.<namespace>.svc.cluster.local`

---

This structure provides **production-grade infrastructure-as-code** with clear separation of concerns, reusability, and safety mechanisms for managing complex Kubernetes deployments.
