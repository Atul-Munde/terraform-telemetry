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
# ILM Policies
# =============================================================================

# Global ILM policy — hot for retention_days, then delete
resource "elasticstack_elasticsearch_index_lifecycle" "global" {
  name = "telemetry-global-${var.retention_days}d"

  hot {
    min_age = "0ms"
    set_priority {
      priority = 100
    }
  }

  delete {
    min_age = "${var.retention_days}d"
    delete {}
  }

  depends_on = [helm_release.elasticsearch]
}

# Custom ILM policies — per-index overrides with longer retention
resource "elasticstack_elasticsearch_index_lifecycle" "custom" {
  for_each = var.custom_ilm_policies

  name = "telemetry-${each.key}-${each.value}d"

  hot {
    min_age = "0ms"
    set_priority {
      priority = 100
    }
  }

  delete {
    min_age = "${each.value}d"
    delete {}
  }

  depends_on = [helm_release.elasticsearch]
}

# =============================================================================
# Index Templates — attach ILM policies to index patterns
# =============================================================================

# Global index template — matches all indices, lowest priority
resource "elasticstack_elasticsearch_index_template" "global" {
  name           = "telemetry-global-ilm"
  index_patterns = ["*"]
  priority       = 99

  template {
    settings = jsonencode({
      "index.lifecycle.name" = elasticstack_elasticsearch_index_lifecycle.global.name
    })
  }

  depends_on = [elasticstack_elasticsearch_index_lifecycle.global]
}

# Custom index templates — higher priority, override global for specific indices
resource "elasticstack_elasticsearch_index_template" "custom" {
  for_each = var.custom_ilm_policies

  name           = "telemetry-${each.key}-ilm"
  index_patterns = ["${each.key}-*", "${each.key}*"]
  priority       = 200

  template {
    settings = jsonencode({
      "index.lifecycle.name" = elasticstack_elasticsearch_index_lifecycle.custom[each.key].name
    })
  }

  depends_on = [elasticstack_elasticsearch_index_lifecycle.custom]
}
