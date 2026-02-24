# Infra credentials Secret
# Only created when infra_metrics_enabled = true
# Production: use External Secrets Operator + AWS Secrets Manager instead of
# storing values in Terraform state. These variables should be sourced from
# environment variables (TF_VAR_mongodb_password etc.) or a secrets backend.

resource "kubernetes_secret" "otel_infra_credentials" {
  count = var.infra_metrics_enabled ? 1 : 0

  metadata {
    name      = "otel-infra-credentials"
    namespace = var.namespace
    labels    = merge(local.common_labels, {
      "app.kubernetes.io/component" = "otel-infra-metrics"
    })
  }

  type = "Opaque"

  data = {
    mongodb-password    = var.mongodb_password
    rabbitmq-password   = var.rabbitmq_password
    postgresql-password = var.postgresql_password
  }
}
