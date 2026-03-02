locals {
  release_name = "jaeger"
  chart_repo   = "https://jaegertracing.github.io/helm-charts"

  # ALB annotations — internet-facing, HTTPS-only, IP target mode.
  alb_annotations = merge(
    {
      "alb.ingress.kubernetes.io/scheme"                       = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"                  = "ip"
      "alb.ingress.kubernetes.io/certificate-arn"              = var.alb_certificate_arn
      "alb.ingress.kubernetes.io/listen-ports"                 = "[{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"                 = "443"
      "alb.ingress.kubernetes.io/healthcheck-path"             = "/"
      "alb.ingress.kubernetes.io/healthcheck-interval-seconds" = "15"
      "alb.ingress.kubernetes.io/healthcheck-timeout-seconds"  = "5"
      "alb.ingress.kubernetes.io/healthy-threshold-count"      = "2"
      "alb.ingress.kubernetes.io/unhealthy-threshold-count"    = "3"
    },
    var.alb_group_name != "" ? {
      "alb.ingress.kubernetes.io/group.name" = var.alb_group_name
    } : {}
  )
}

# Jaeger Helm Release
resource "helm_release" "jaeger" {
  name       = local.release_name
  repository = local.chart_repo
  chart      = "jaeger"
  version    = var.chart_version
  namespace  = var.namespace
  timeout    = 600
  cleanup_on_fail = true

  values = [
    templatefile("${path.module}/templates/values.yaml.tpl", {
      storage_type           = var.storage_type
      elasticsearch_host     = var.elasticsearch_host
      elasticsearch_port     = var.elasticsearch_port
      elasticsearch_user     = var.elastic_username
      elasticsearch_password = var.elastic_password
      es_auth_enabled        = var.elastic_password != ""
      collector_replicas     = var.collector_replicas
      query_replicas         = var.query_replicas
      environment            = var.environment
      node_selector          = var.node_selector
      tolerations            = var.tolerations
    })
  ]
}

# ---------------------------------------------------------------------------
# ALB Ingress (optional — enabled via create_ingress = true)
# ---------------------------------------------------------------------------
resource "kubernetes_ingress_v1" "jaeger" {
  count = var.create_ingress ? 1 : 0

  metadata {
    name      = "jaeger"
    namespace = var.namespace
    labels = merge(var.labels, {
      "app.kubernetes.io/name"       = "jaeger"
      "app.kubernetes.io/component"  = "ingress"
      "app.kubernetes.io/managed-by" = "terraform"
    })
    annotations = local.alb_annotations
  }

  spec {
    ingress_class_name = var.ingress_class_name

    rule {
      host = var.ingress_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "${local.release_name}-query"
              port {
                number = 16686
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.jaeger]
}
