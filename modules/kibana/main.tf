locals {
  # Node.js heap = 50% of container memory limit (mirrors Elasticsearch heap convention)
  memory_limit_mb = tonumber(regex("([0-9]+)", var.resources.limits.memory)[0]) * (
    can(regex("Gi", var.resources.limits.memory)) ? 1024 : 1
  )
  heap_size_mb = floor(local.memory_limit_mb * 0.5)

  secret_name = "kibana-credentials"

  # ALB annotations — internet-facing, HTTPS-only, IP target mode.
  # 'kubernetes.io/ingress.class' annotation intentionally omitted —
  # aws-load-balancer-controller v2.x uses spec.ingressClassName instead.
  alb_annotations = merge(
    {
      "alb.ingress.kubernetes.io/scheme"                       = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"                  = "ip"
      "alb.ingress.kubernetes.io/certificate-arn"              = var.alb_certificate_arn
      "alb.ingress.kubernetes.io/listen-ports"                 = "[{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"                 = "443"
      "alb.ingress.kubernetes.io/healthcheck-path"             = "/api/status"
      "alb.ingress.kubernetes.io/healthcheck-interval-seconds" = "15"
      "alb.ingress.kubernetes.io/healthcheck-timeout-seconds"  = "5"
      "alb.ingress.kubernetes.io/healthy-threshold-count"      = "2"
      "alb.ingress.kubernetes.io/unhealthy-threshold-count"    = "3"
    },
    # When set, Ingress joins the existing shared ALB (no new ALB created).
    # When empty, controller provisions a dedicated ALB for Kibana.
    var.alb_group_name != "" ? {
      "alb.ingress.kubernetes.io/group.name" = var.alb_group_name
    } : {}
  )
}

# ---------------------------------------------------------------------------
# Credentials secret — passwords never stored in Helm values or tfvars
# ---------------------------------------------------------------------------
resource "kubernetes_secret" "kibana_credentials" {
  metadata {
    name      = local.secret_name
    namespace = var.namespace
    labels = merge(var.labels, {
      "app.kubernetes.io/name"       = "kibana"
      "app.kubernetes.io/component"  = "credentials"
      "app.kubernetes.io/managed-by" = "terraform"
    })
  }

  type = "Opaque"

  # sensitive values — Terraform will not print these in plan/apply output
  data = {
    ELASTICSEARCH_PASSWORD = var.elastic_password
    KIBANA_ENCRYPTION_KEY  = var.kibana_encryption_key
  }
}

# ---------------------------------------------------------------------------
# Kibana Helm Release
# ---------------------------------------------------------------------------
resource "helm_release" "kibana" {
  name             = "kibana"
  repository       = "https://helm.elastic.co"
  chart            = "kibana"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = false
  timeout          = 600
  force_update     = true
  recreate_pods    = false
  cleanup_on_fail  = true

  values = [
    templatefile("${path.module}/templates/values.yaml.tpl", {
      replicas                  = var.replicas
      resources_requests_cpu    = var.resources.requests.cpu
      resources_requests_memory = var.resources.requests.memory
      resources_limits_cpu      = var.resources.limits.cpu
      resources_limits_memory   = var.resources.limits.memory
      heap_size_mb              = local.heap_size_mb
      elasticsearch_host        = var.elasticsearch_host
      secret_name               = local.secret_name
      storage_class             = var.storage_class
      storage_size              = var.storage_size
      node_selector             = var.node_selector
      tolerations               = var.tolerations
      log_level                 = var.log_level
      base_path                 = var.base_path
    })
  ]

  # Secret must exist before Helm creates the Kibana deployment
  depends_on = [kubernetes_secret.kibana_credentials]
}

# ---------------------------------------------------------------------------
# ALB Ingress (optional — enabled via create_ingress = true)
# ---------------------------------------------------------------------------
resource "kubernetes_ingress_v1" "kibana" {
  count = var.create_ingress ? 1 : 0

  metadata {
    name      = "kibana"
    namespace = var.namespace
    labels = merge(var.labels, {
      "app.kubernetes.io/name"       = "kibana"
      "app.kubernetes.io/component"  = "ingress"
      "app.kubernetes.io/managed-by" = "terraform"
    })
    annotations = local.alb_annotations
  }

  spec {
    # Modern field — replaces the deprecated kubernetes.io/ingress.class annotation
    ingress_class_name = var.ingress_class_name

    rule {
      host = var.ingress_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "kibana-kibana"
              port {
                number = 5601
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.kibana]
}
