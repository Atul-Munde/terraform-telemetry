# RBAC for VictoriaMetrics components
# VMAgent requires a ClusterRole to discover Kubernetes resources (pods, nodes,
# endpoints, services) for service discovery and metrics collection.

# ---------------------------------------------------------------------------
# VMAgent ServiceAccount
# ---------------------------------------------------------------------------
resource "kubernetes_service_account" "vmagent" {
  count = var.vmagent_enabled ? 1 : 0

  metadata {
    name      = "vmagent"
    namespace = var.namespace
    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "vmagent"
    })
  }
}

# ClusterRole — VMAgent needs broad read access for Kubernetes service discovery
resource "kubernetes_cluster_role" "vmagent" {
  count = var.vmagent_enabled ? 1 : 0

  metadata {
    # Namespace-scoped name prevents collisions when multiple environments
    # deploy to the same cluster (e.g., telemetry-dev, telemetry-staging)
    name = "vmagent-${var.namespace}"
    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "vmagent"
    })
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "nodes/metrics", "nodes/proxy", "services", "endpoints", "pods", "namespaces"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["extensions", "networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["discovery.k8s.io"]
    resources  = ["endpointslices"]
    verbs      = ["get", "list", "watch"]
  }

  # Required for scraping kubelet /metrics/cadvisor endpoint
  rule {
    non_resource_urls = ["/metrics", "/metrics/cadvisor", "/metrics/resource", "/metrics/probes"]
    verbs             = ["get"]
  }

  # Required for VMAgent to list/watch its own CRD config
  rule {
    api_groups = ["operator.victoriametrics.com"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "vmagent" {
  count = var.vmagent_enabled ? 1 : 0

  metadata {
    name = "vmagent-${var.namespace}"
    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "vmagent"
    })
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.vmagent[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vmagent[0].metadata[0].name
    namespace = var.namespace
  }
}

# ---------------------------------------------------------------------------
# VMAgent namespace-scoped Role — read the operator-generated scrape config secret
# The VM Operator stores VMAgent's generated scrape config in a Secret named
# "vmagent-<name>" in the telemetry namespace. The config-init init container
# reads it via the ServiceAccount token, so the SA needs secrets get/list/watch.
# ---------------------------------------------------------------------------
resource "kubernetes_role" "vmagent_secret" {
  count = var.vmagent_enabled ? 1 : 0

  metadata {
    name      = "vmagent-secret-reader"
    namespace = var.namespace
    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "vmagent"
    })
  }

  rule {
    api_groups = [""]
    resources  = ["secrets", "configmaps"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding" "vmagent_secret" {
  count = var.vmagent_enabled ? 1 : 0

  metadata {
    name      = "vmagent-secret-reader"
    namespace = var.namespace
    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "vmagent"
    })
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.vmagent_secret[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vmagent[0].metadata[0].name
    namespace = var.namespace
  }
}

# ---------------------------------------------------------------------------
# VMAlert ServiceAccount (minimal — only needs to call vmselect + vminsert)
# ---------------------------------------------------------------------------
resource "kubernetes_service_account" "vmalert" {
  count = var.vmalert_enabled ? 1 : 0

  metadata {
    name      = "vmalert"
    namespace = var.namespace
    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "vmalert"
    })
  }
}
