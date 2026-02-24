# RBAC for OTel Agent and Gateway
# Agent: broad ClusterRole for k8sattributes + kubeletstats + resourcedetection
# Gateway: minimal role (future-proofed for k8sattributes if needed)

# -----------------------------------------------------------------------
# Agent ServiceAccount
# -----------------------------------------------------------------------
resource "kubernetes_service_account" "otel_agent" {
  metadata {
    name      = "otel-agent"
    namespace = var.namespace
    labels    = merge(local.common_labels, {
      "app.kubernetes.io/component" = "otel-agent"
    })
  }
}

# -----------------------------------------------------------------------
# Agent ClusterRole
# Required by:
#   - k8sattributes processor: pods, namespaces, nodes, endpoints, replicasets
#   - kubeletstats receiver:   nodes/stats, nodes/proxy
#   - resourcedetection/eks:   nodes (covered above)
# -----------------------------------------------------------------------
resource "kubernetes_cluster_role" "otel_agent" {
  metadata {
    name   = "otel-agent-${var.namespace}"
    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "otel-agent"
    })
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "nodes/stats", "nodes/proxy", "pods", "namespaces", "endpoints"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["replicasets", "deployments", "statefulsets", "daemonsets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["replicasets"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "otel_agent" {
  metadata {
    name   = "otel-agent-${var.namespace}"
    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "otel-agent"
    })
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.otel_agent.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.otel_agent.metadata[0].name
    namespace = var.namespace
  }
}

# -----------------------------------------------------------------------
# Gateway ServiceAccount
# -----------------------------------------------------------------------
resource "kubernetes_service_account" "otel_gateway" {
  metadata {
    name      = "otel-gateway"
    namespace = var.namespace
    labels    = merge(local.common_labels, {
      "app.kubernetes.io/component" = "otel-gateway"
    })
  }
}

# Minimal ClusterRole for Gateway — future-proofed if k8sattributes is added
resource "kubernetes_cluster_role" "otel_gateway" {
  metadata {
    name   = "otel-gateway-${var.namespace}"
    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "otel-gateway"
    })
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "namespaces"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "otel_gateway" {
  metadata {
    name   = "otel-gateway-${var.namespace}"
    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "otel-gateway"
    })
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.otel_gateway.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.otel_gateway.metadata[0].name
    namespace = var.namespace
  }
}
