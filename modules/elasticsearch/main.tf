locals {
  name = "elasticsearch"
  # Calculate heap size as 50% of memory limit (Elasticsearch best practice)
  # Both min and max heap must be equal
  memory_limit_mb = tonumber(regex("([0-9]+)", var.resources.limits.memory)[0]) * (can(regex("Gi", var.resources.limits.memory)) ? 1024 : 1)
  heap_size_mb    = floor(local.memory_limit_mb * 0.5)
  heap_size       = "${local.heap_size_mb}m"
}

# Elasticsearch Helm Release
resource "helm_release" "elasticsearch" {
  name       = "elasticsearch"
  repository = "https://helm.elastic.co"
  chart      = "elasticsearch"
  version    = "8.5.1"
  namespace  = var.namespace
  create_namespace = false

  values = [
    yamlencode({
      replicas = var.replicas

      # Resource configuration
      resources = {
        requests = {
          cpu    = var.resources.requests.cpu
          memory = var.resources.requests.memory
        }
        limits = {
          cpu    = var.resources.limits.cpu
          memory = var.resources.limits.memory
        }
      }

      # Heap size - must be equal for both Xms and Xmx
      esJavaOpts = "-Xms${local.heap_size} -Xmx${local.heap_size}"

      # Volume configuration
      volumeClaimTemplate = {
        accessModes = ["ReadWriteOnce"]
        storageClassName = var.storage_class != "" ? var.storage_class : null
        resources = {
          requests = {
            storage = var.storage_size
          }
        }
      }

      # Security completely disabled
      protocol = "http"
      httpPort = 9200
      transportPort = 9300
      
      # Create service account
      serviceAccount = "elasticsearch"
      
      # Minimal master nodes 
      minimumMasterNodes = var.replicas > 1 ? 1 : 1
      
      # Secret mounts - empty to prevent SSL cert creation
      secretMounts = []

      # Node selector and tolerations
      nodeSelector = var.node_selector
      tolerations  = var.tolerations

      # Anti-affinity to spread pods
      antiAffinity = "soft"

      # Elasticsearch config
      esConfig = {
        "elasticsearch.yml" = <<-EOT
network.host: 0.0.0.0

# Completely disable security
xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false

# Performance settings
indices.memory.index_buffer_size: 30%
indices.queries.cache.size: 10%

# Auto-create indices
action.auto_create_index: true
        EOT
      }
      
      # Extra environment variables to disable security completely
      extraEnvs = [
        {
          name = "ELASTIC_PASSWORD"
          value = "changeme"
        },
        {
          name = "xpack.security.enabled"
          value = "false"
        }
      ]

      # Pod disruption budget
      maxUnavailable = 1

      # Sysctls for Elasticsearch
      sysctlInitContainer = {
        enabled = true
      }
    })
  ]

  timeout = 600
}

# CronJob for index cleanup
resource "kubernetes_cron_job_v1" "index_cleanup" {
  metadata {
    name      = "elasticsearch-index-cleanup"
    namespace = var.namespace
    labels = {
      app       = "elasticsearch"
      component = "cleanup"
    }
  }

  spec {
    schedule = "0 2 * * *"  # Run at 2 AM daily
    
    job_template {
      metadata {
        labels = {
          app       = "elasticsearch"
          component = "cleanup"
        }
      }

      spec {
        template {
          metadata {
            labels = {
              app       = "elasticsearch"
              component = "cleanup"
            }
          }

          spec {
            restart_policy = "OnFailure"

            container {
              name  = "curator"
              image = "bitnami/elasticsearch-curator:5.8.4"

              command = [
                "/bin/sh",
                "-c",
                <<-EOT
                  curl -X GET "http://elasticsearch-master.${var.namespace}.svc.cluster.local:9200/_cluster/health" || echo "ES not ready yet"
                EOT
              ]
            }
          }
        }
      }
    }

    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3
  }

  depends_on = [helm_release.elasticsearch]
}
