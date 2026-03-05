locals {
  name = "elasticsearch"
  # Calculate heap size as 50% of memory limit (Elasticsearch best practice)
  memory_limit_mb = tonumber(regex("([0-9]+)", var.resources.limits.memory)[0]) * (can(regex("Gi", var.resources.limits.memory)) ? 1024 : 1)
  heap_size_mb    = floor(local.memory_limit_mb * 0.5)
  heap_size       = "${local.heap_size_mb}m"
}

# Elasticsearch credentials secret — password never stored in Helm values or tfvars
resource "kubernetes_secret" "elasticsearch_credentials" {
  count = var.elastic_password != "" ? 1 : 0

  metadata {
    name      = "elasticsearch-credentials"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "elasticsearch"
      "app.kubernetes.io/component"  = "credentials"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  type = "Opaque"

  data = {
    ELASTIC_PASSWORD = var.elastic_password
  }
}

# Elasticsearch Helm Release
resource "helm_release" "elasticsearch" {
  name             = "elasticsearch"
  repository       = "https://helm.elastic.co"
  chart            = "elasticsearch"
  version          = "8.5.1"
  namespace        = var.namespace
  create_namespace = false
  timeout          = 600

  values = [
    templatefile("${path.module}/templates/values.yaml.tpl", {
      replicas                  = var.replicas
      resources_requests_cpu    = var.resources.requests.cpu
      resources_requests_memory = var.resources.requests.memory
      resources_limits_cpu      = var.resources.limits.cpu
      resources_limits_memory   = var.resources.limits.memory
      heap_size                 = local.heap_size
      storage_class             = var.storage_class
      storage_size              = var.storage_size
      node_selector             = var.node_selector
      tolerations               = var.tolerations
      xpack_security_enabled    = var.elastic_password != ""
      elastic_secret_name       = var.elastic_password != "" ? "elasticsearch-credentials" : ""
      elastic_password          = var.elastic_password
    })
  ]

  depends_on = [kubernetes_secret.elasticsearch_credentials]
}

# CronJob for index cleanup — deletes indices older than retention_days
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
    schedule = "0 2 * * *" # Run at 2 AM daily

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
              name  = "cleanup"
              image = "curlimages/curl:8.5.0"

              command = [
                "/bin/sh",
                "-c",
                <<-EOT
                  ES_URL="${var.elastic_password != "" ? "https" : "http"}://elasticsearch-master.${var.namespace}.svc.cluster.local:9200"
                  AUTH="${var.elastic_password != "" ? "-u elastic:${var.elastic_password} --insecure" : ""}"
                  echo "Deleting indices older than ${var.retention_days} days..."
                  curl -s $AUTH -X DELETE "$ES_URL/*-*$(date -d "-${var.retention_days} days" +%Y.%m.%d 2>/dev/null || date -v-${var.retention_days}d +%Y.%m.%d)*" || true
                  curl -s $AUTH -X DELETE "$ES_URL/jaeger-span-*" --data '{"query":{"range":{"startTimeMillis":{"lt":"now-${var.retention_days}d"}}}}' -H 'Content-Type: application/json' || true
                  echo "Cleanup complete."
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
