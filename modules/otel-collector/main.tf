locals {
  name = "otel-collector"
  labels = merge(
    {
      app       = local.name
      component = "collector"
      part-of   = "telemetry"
    },
    var.labels
  )
}
