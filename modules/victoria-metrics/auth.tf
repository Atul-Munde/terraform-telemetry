# VMAuth — routes insert/select traffic and provides basic authentication
# Acts as a reverse proxy in front of vminsert (port 8480) and vmselect (port 8481).
# Only deployed when vmauth_enabled = true.

resource "kubernetes_secret" "vmauth_credentials" {
  count = var.vmauth_enabled && var.vmauth_password != "" ? 1 : 0

  metadata {
    name      = "vmauth-credentials"
    namespace = var.namespace
    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "vmauth"
    })
  }

  type = "Opaque"
  data = {
    password = var.vmauth_password
  }
}

# VMUser — declares a named user that VMAuth references for authentication
resource "kubectl_manifest" "vmuser" {
  count = var.vmauth_enabled && var.vmauth_password != "" ? 1 : 0

  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMUser"
    metadata = {
      name      = "vmuser-default"
      namespace = var.namespace
      labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "vmauth" })
    }
    spec = {
      name     = "default"
      username = "vmuser"
      passwordRef = {
        name = kubernetes_secret.vmauth_credentials[0].metadata[0].name
        key  = "password"
      }
      # Route /insert/* to vminsert, /select/* to vmselect
      targetRefs = [
        {
          crd = {
            kind      = "VMCluster/vminsert"
            name      = var.vm_cluster_name
            namespace = var.namespace
          }
          paths = ["/insert/.*", "/prometheus/api/v1/write", "/opentelemetry/.*"]
        },
        {
          crd = {
            kind      = "VMCluster/vmselect"
            name      = var.vm_cluster_name
            namespace = var.namespace
          }
          paths = ["/select/.*", "/prometheus/.*", "/vmui/.*", "/health"]
        }
      ]
    }
  })

  depends_on = [kubectl_manifest.vmcluster]
}

# VMAuth — the actual auth proxy CR
resource "kubectl_manifest" "vmauth" {
  count = var.vmauth_enabled ? 1 : 0

  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMAuth"
    metadata = {
      name      = "vmauth"
      namespace = var.namespace
      labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "vmauth" })
    }
    spec = {
      # Select all VMUser objects in this namespace
      userSelector = {
        matchLabels = local.common_labels
      }

      replicaCount = 2

      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "300m", memory = "256Mi" }
      }

      podDisruptionBudget = {
        minAvailable = 1
      }

      securityContext = {
        runAsNonRoot = true
        runAsUser    = 65534
      }

      # Ingress is managed exclusively by ingress.tf (kubernetes_ingress_v1.vmselect_ui),
      # which routes to vmauth-vmauth:8427 when vmauth_enabled = true.
      # Do NOT set the ingress field here — the operator would create a second
      # Ingress on the same ALB group/host, conflicting with the one from ingress.tf.

      nodeSelector = length(var.node_selector) > 0 ? var.node_selector : null
    }
  })

  depends_on = [kubectl_manifest.vmcluster]
}
