# VMAgent — scrapes Kubernetes cluster metrics and remote-writes to VMCluster
# Uses Kubernetes service discovery to find all scrape targets in the cluster.
# Only deployed when vmagent_enabled = true.

resource "kubectl_manifest" "vmagent" {
  count = var.vmagent_enabled ? 1 : 0

  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMAgent"
    metadata = {
      name      = "vmagent"
      namespace = var.namespace
      labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "vmagent" })
    }
    spec = {
      replicaCount = 2

      # Scrape all VMServiceScrapes and ServiceMonitors across the telemetry namespace.
      # Set selectAllByDefault=true to auto-discover all scrape targets without
      # needing explicit selectors on each VMServiceScrape.
      selectAllByDefault = true

      # Remote write — send all scraped metrics into VMCluster vminsert
      remoteWrite = [
        {
          url = "${local.vminsert_url}/insert/0/prometheus/api/v1/write"
        }
      ]

      serviceAccountName = kubernetes_service_account.vmagent[0].metadata[0].name

      resources = {
        requests = {
          cpu    = local._norm_cpu.va_req
          memory = var.vmagent_resources.requests.memory
        }
        limits = {
          cpu    = local._norm_cpu.va_lim
          memory = var.vmagent_resources.limits.memory
        }
      }

      podDisruptionBudget = {
        minAvailable = 1
      }

      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 100
              podAffinityTerm = {
                topologyKey = "kubernetes.io/hostname"
                labelSelector = {
                  matchLabels = {
                    "app.kubernetes.io/name" = "vmagent"
                  }
                }
              }
            }
          ]
        }
      }

      securityContext = {
        runAsNonRoot = true
        runAsUser    = 65534
        runAsGroup   = 65534
      }

      # On-disk write-ahead log: buffer metrics when vminsert is temporarily unavailable
      # File size ~500Mi gives ~5-10 min of buffer at typical ingestion rates
      extraArgs = {
        "remoteWrite.maxDiskUsagePerURL" = "500MB"
        "remoteWrite.queues"             = "4"
      }

      nodeSelector = length(var.node_selector) > 0 ? var.node_selector : null
      tolerations  = [
        for t in var.tolerations : merge(
          { key = t.key, operator = t.operator },
          t.value  != null ? { value  = t.value }  : {},
          t.effect != null ? { effect = t.effect }  : {}
        )
      ]
    }
  })

  depends_on = [
    kubectl_manifest.vmcluster,
    kubernetes_service_account.vmagent,
    kubernetes_cluster_role_binding.vmagent,
    kubernetes_role_binding.vmagent_secret,
  ]
}
