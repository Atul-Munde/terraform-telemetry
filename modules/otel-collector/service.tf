resource "kubernetes_service" "otel_collector" {
  metadata {
    name      = local.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = local.name
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
      protocol    = "TCP"
    }

    port {
      name        = "health"
      port        = 13133
      target_port = 13133
      protocol    = "TCP"
    }

    port {
      name        = "zpages"
      port        = 55679
      target_port = 55679
      protocol    = "TCP"
    }

    session_affinity = "None"
  }
}
