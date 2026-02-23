resource "kubernetes_namespace" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name        = var.namespace
    labels      = var.labels
    annotations = var.annotations
  }
}

# Create a local to handle both created and existing namespaces
locals {
  namespace_name = var.create_namespace ? kubernetes_namespace.this[0].metadata[0].name : var.namespace
}
