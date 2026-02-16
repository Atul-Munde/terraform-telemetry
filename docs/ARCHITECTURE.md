# Project Structure

```
otel_terrform/
├── README.md                           # Main documentation
├── Makefile                           # Convenience commands
├── .gitignore                         # Git ignore rules
│
├── main.tf                            # Root module entry point
├── variables.tf                       # Root variables
├── outputs.tf                         # Root outputs
├── versions.tf                        # Provider versions
├── backend.tf                         # Remote state configuration
├── terraform.tfvars.example           # Example variables
│
├── modules/                           # Terraform modules
│   ├── namespace/                     # Namespace module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── otel-collector/                # OpenTelemetry Collector module
│   │   ├── main.tf                    # Module entry
│   │   ├── variables.tf               # Input variables
│   │   ├── outputs.tf                 # Output values
│   │   ├── configmap.tf               # OTel config
│   │   ├── deployment.tf              # Deployment + RBAC
│   │   ├── service.tf                 # Kubernetes service
│   │   └── hpa.tf                     # Horizontal Pod Autoscaler
│   │
│   ├── jaeger/                        # Jaeger module (Helm)
│   │   ├── main.tf                    # Helm release
│   │   ├── variables.tf               # Input variables
│   │   └── outputs.tf                 # Output values
│   │
│   └── elasticsearch/                 # Elasticsearch module
│       ├── main.tf                    # Helm release deployment
│       ├── variables.tf               # Input variables
│       └── outputs.tf                 # Output values
│
├── environments/                      # Environment-specific configs
│   ├── dev/
│   │   ├── main.tf                    # Dev environment config
│   │   └── terraform.tfvars           # Dev variables (gitignored)
│   │
│   ├── staging/
│   │   ├── main.tf                    # Staging environment config
│   │   └── terraform.tfvars           # Staging variables (gitignored)
│   │
│   └── production/
│       ├── main.tf                    # Production environment config
│       └── terraform.tfvars           # Production variables (gitignored)
│
├── scripts/                           # Helper scripts
│   ├── deploy.sh                      # Deployment script
│   ├── cleanup.sh                     # Cleanup script
│   └── validate.sh                    # Health check script
│
└── docs/                              # Documentation
    ├── QUICKSTART.md                  # Quick start guide
    ├── DEPLOYMENT.md                  # Detailed deployment guide
    └── APPLICATION_INTEGRATION.md     # App integration guide
```

## Module Dependencies

```
main.tf (root)
├── namespace module
├── elasticsearch module
│   └── depends on: namespace
├── jaeger module
│   └── depends on: namespace, elasticsearch
└── otel-collector module
    └── depends on: namespace, jaeger
```

## Key Files Description

### Root Level

- **main.tf**: Orchestrates all modules, defines providers
- **variables.tf**: Declares all input variables with validation
- **outputs.tf**: Exports important values (endpoints, commands)
- **versions.tf**: Pins Terraform and provider versions
- **backend.tf**: Remote state configuration (S3, GCS, etc.)

### Modules

#### namespace/
Creates or references Kubernetes namespace for isolation.

#### otel-collector/
- **configmap.tf**: YAML configuration for receivers, processors, exporters
- **deployment.tf**: Pod spec, RBAC, resource limits, probes
- **service.tf**: ClusterIP service exposing OTLP endpoints
- **hpa.tf**: Auto-scaling based on CPU/memory metrics

#### jaeger/
- **main.tf**: Helm chart deployment with customized values
  - Collector for receiving traces
  - Query service for UI and API
  - Elasticsearch storage integration

#### elasticsearch/
- **main.tf**: Helm chart deployment with:
  - Official Elastic Helm chart (elastic/elasticsearch)
  - Persistent volumes for data (gp3 storage)
  - Dynamic heap size configuration (50% of memory limit)
  - Security settings (xpack.security disabled for internal use)
  - Sysctls for vm.max_map_count
  - Master-eligible nodes with proper anti-affinity

### Environments

Each environment (dev/staging/production) has:
- **main.tf**: Imports root module with env-specific values
- **terraform.tfvars**: Environment-specific variable overrides

Configuration differences by environment:
- **Dev**: Minimal resources, single replicas, short retention
- **Staging**: Medium resources, 2 replicas, moderate retention
- **Production**: High resources, 3+ replicas, long retention, sampling enabled

### Scripts

- **deploy.sh**: Automated deployment with checks and confirmations
- **cleanup.sh**: Safe destruction with multiple confirmations
- **validate.sh**: Health checks for all components

### Documentation

- **QUICKSTART.md**: Get running in 5 minutes
- **DEPLOYMENT.md**: Complete deployment guide with troubleshooting
- **APPLICATION_INTEGRATION.md**: How to integrate applications with examples

## Resource Naming Convention

```
Component                 Resource Type              Name
---------------------------------------------------------------------------
OTel Collector           Deployment                 otel-collector
                         Service                    otel-collector
                         ConfigMap                  otel-collector-config
                         ServiceAccount             otel-collector
                         HPA                        otel-collector-hpa

Jaeger                   Helm Release               jaeger
                         Service (Query)            jaeger-query
                         Service (Collector)        jaeger-collector

Elasticsearch            Helm Release               elasticsearch
                         StatefulSet                elasticsearch-master
                         Service                    elasticsearch-master (headless)
                         Service                    elasticsearch-master-headless
                         PVC                        elasticsearch-master-elasticsearch-master-{0,1}
```

## Port Assignments

```
Service               Port    Purpose
---------------------------------------------------------------------------
OTel Collector        4317    OTLP gRPC receiver
                      4318    OTLP HTTP receiver
                      8888    Metrics (Prometheus)
                      13133   Health check
                      55679   zPages

Jaeger Collector      14250   gRPC from OTel
                      14268   HTTP
                      4317    OTLP gRPC
                      4318    OTLP HTTP

Jaeger Query          16686   UI and API

Elasticsearch         9200    HTTP API
                      9300    Transport (inter-node)
```

## Configuration Flow

```
1. terraform.tfvars (environment)
   ↓
2. main.tf (environment)
   ↓
3. modules/**/variables.tf
   ↓
4. modules/**/main.tf (resource creation)
   ↓
5. Kubernetes resources
```

## State Management

```
Local Development:
  terraform.tfstate (local file, gitignored)

Production:
  S3 bucket + DynamoDB (or equivalent)
  backend.tf configures remote state
  State locking prevents concurrent modifications
```

## Secrets Management

Current implementation:
- No sensitive data required for basic setup
- Elasticsearch runs without authentication (internal only)

Production recommendations:
- Use Kubernetes Secrets for credentials
- Integrate with external secret managers:
  - AWS Secrets Manager
  - HashiCorp Vault
  - Azure Key Vault
  - Google Secret Manager

## Extension Points

Want to extend the setup? Here are the key extension points:

1. **Add more exporters to OTel Collector**:
   - Edit `modules/otel-collector/configmap.tf`
   - Add exporter config in `exporters` section
   - Update pipeline to include new exporter

2. **Enable metrics/logs pipelines**:
   - Add receivers in configmap
   - Configure new pipelines in `service.pipelines`

3. **Add Ingress for Jaeger UI**:
   - Create ingress.tf in jaeger module
   - Configure TLS with cert-manager

4. **Integrate with Prometheus**:
   - OTel Collector already exposes metrics on :8888
   - Add ServiceMonitor CRD for Prometheus Operator

5. **Add NetworkPolicies**:
   - Create network-policies.tf in each module
   - Define allowed traffic between components

## Terraform State File Structure

```
terraform.tfstate
├── version
├── terraform_version
├── serial
├── lineage
└── resources[]
    ├── module.namespace
    ├── module.elasticsearch[0]
    ├── module.jaeger
    └── module.otel_collector
```

## Best Practices Implemented

✅ Modular architecture for reusability
✅ Environment-specific configurations
✅ Resource limits and requests
✅ Health probes (liveness/readiness)
✅ High availability (multiple replicas)
✅ Auto-scaling (HPA)
✅ Pod disruption budgets
✅ Anti-affinity rules
✅ Rolling update strategies
✅ Meaningful labels and annotations
✅ Descriptive variable validation
✅ Comprehensive outputs
✅ Version pinning
✅ Documentation

## Maintenance

### Regular Updates

1. **Terraform providers**:
   ```bash
   terraform init -upgrade
   ```

2. **OTel Collector version**:
   - Update `otel_collector_version` variable
   - Test in dev first

3. **Jaeger chart**:
   - Update `jaeger_chart_version` variable
   - Review chart release notes

4. **Elasticsearch**:
   - Update image in elasticsearch module
   - Plan data migration if needed

### Monitoring

Create alerts for:
- Pod crashes/restarts
- High memory usage
- Disk space on Elasticsearch PVCs
- HPA scale events
- Failed span exports

### Backup Strategy

**Elasticsearch data**:
1. Configure snapshot repository
2. Schedule regular snapshots
3. Test restore procedures

**Terraform state**:
1. Use remote backend with versioning
2. Enable state locking
3. Regular state backups
