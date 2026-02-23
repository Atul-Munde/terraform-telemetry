locals {
  name = "elasticsearch"
  # Calculate heap size as 50% of memory limit (Elasticsearch best practice)
  memory_limit_mb = tonumber(regex("([0-9]+)", var.resources.limits.memory)[0]) * (can(regex("Gi", var.resources.limits.memory)) ? 1024 : 1)
  heap_size_mb    = floor(local.memory_limit_mb * 0.5)
  heap_size       = "${local.heap_size_mb}m"
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
    })
  ]
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
