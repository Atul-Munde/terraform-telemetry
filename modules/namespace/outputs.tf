output "name" {
  description = "Namespace name"
  value       = local.namespace_name
}

output "id" {
  description = "Namespace ID"
  value       = var.create_namespace ? kubernetes_namespace.this[0].id : var.namespace
}
