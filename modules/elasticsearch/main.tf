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

# =============================================================================
# ILM Policies & Index Templates — applied via Kubernetes Job (no elasticstack provider)
# The Job runs after ES is ready, creates ILM policies and index templates via curl.
# =============================================================================

locals {
  es_url = "https://elasticsearch-master.${var.namespace}.svc.cluster.local:9200"

  # Build curl commands for custom ILM policies
  custom_ilm_commands = join("\n\n", [
    for prefix, days in var.custom_ilm_policies : <<-EOT
    # Custom ILM policy — ${prefix} ${days} days
    curl -sk -u "elastic:$PASSWORD" -X PUT \
      "https://elasticsearch-master:9200/_ilm/policy/telemetry-${prefix}-${days}d" \
      -H 'Content-Type: application/json' -d '{
        "policy": {
          "phases": {
            "hot":    { "min_age": "0ms", "actions": { "set_priority": { "priority": 100 } } },
            "delete": { "min_age": "${days}d",  "actions": { "delete": {} } }
          }
        }
      }'
    EOT
  ])

  # Build curl commands for custom index templates
  custom_template_commands = join("\n\n", [
    for prefix, days in var.custom_ilm_policies : <<-EOT
    # Custom index template — priority 200, overrides global for ${prefix}-*
    curl -sk -u "elastic:$PASSWORD" -X PUT \
      "https://elasticsearch-master:9200/_index_template/telemetry-${prefix}-ilm" \
      -H 'Content-Type: application/json' -d '{
        "index_patterns": ["${prefix}-*", "${prefix}*"],
        "priority": 200,
        "template": {
          "settings": { "index.lifecycle.name": "telemetry-${prefix}-${days}d" }
        }
      }'
    EOT
  ])
}

resource "kubernetes_job_v1" "elasticsearch_ilm_setup" {
  metadata {
    name      = "elasticsearch-ilm-setup"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "elasticsearch-ilm-setup"
      "app.kubernetes.io/component"  = "ilm"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    backoff_limit = 5

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"      = "elasticsearch-ilm-setup"
          "app.kubernetes.io/component" = "ilm"
        }
      }

      spec {
        restart_policy = "OnFailure"

        container {
          name  = "ilm-setup"
          image = "curlimages/curl:latest"

          env {
            name = "PASSWORD"
            value_from {
              secret_key_ref {
                name = "elasticsearch-credentials"
                key  = "ELASTIC_PASSWORD"
              }
            }
          }

          command = ["/bin/sh", "-c"]
          args = [<<-EOF
            # Wait for ES to be ready
            until curl -sk -u "elastic:$PASSWORD" https://elasticsearch-master:9200/_cluster/health; do
              sleep 5
            done

            # Global ILM policy — ${var.retention_days} day retention
            curl -sk -u "elastic:$PASSWORD" -X PUT \
              "https://elasticsearch-master:9200/_ilm/policy/telemetry-global-${var.retention_days}d" \
              -H 'Content-Type: application/json' -d '{
                "policy": {
                  "phases": {
                    "hot":    { "min_age": "0ms", "actions": { "set_priority": { "priority": 100 } } },
                    "delete": { "min_age": "${var.retention_days}d",  "actions": { "delete": {} } }
                  }
                }
              }'

            ${local.custom_ilm_commands}

            # Global index template — priority 99, applies to all indices
            curl -sk -u "elastic:$PASSWORD" -X PUT \
              "https://elasticsearch-master:9200/_index_template/telemetry-global-ilm" \
              -H 'Content-Type: application/json' -d '{
                "index_patterns": ["*"],
                "priority": 99,
                "template": {
                  "settings": { "index.lifecycle.name": "telemetry-global-${var.retention_days}d" }
                }
              }'

            ${local.custom_template_commands}
          EOF
          ]
        }
      }
    }
  }

  wait_for_completion = false

  depends_on = [helm_release.elasticsearch]
}
