# VMAlert — evaluates alerting and recording rules against VMCluster
# VMRule — defines the alerting rules evaluated by VMAlert
# Both are only deployed when vmalert_enabled = true.

# --- VMRule: alerting rules for VictoriaMetrics HA cluster health ---
resource "kubectl_manifest" "vmrule_victoriametrics" {
  count = var.vmalert_enabled ? 1 : 0

  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMRule"
    metadata = {
      name      = "victoriametrics-alerts"
      namespace = var.namespace
      labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "vmalert" })
    }
    spec = {
      groups = [
        {
          name = "victoriametrics.cluster"
          rules = [
            {
              alert = "VMStorageDown"
              expr  = "up{job=\"vmstorage\"} == 0"
              for   = "2m"
              labels = { severity = "critical", component = "vmstorage" }
              annotations = {
                summary     = "VMStorage pod {{ $labels.pod }} is down"
                description = "VMStorage pod {{ $labels.pod }} has been down for 2m. Data loss risk if RF is insufficient."
              }
            },
            {
              alert = "VMInsertDown"
              expr  = "up{job=\"vminsert\"} == 0"
              for   = "2m"
              labels = { severity = "critical", component = "vminsert" }
              annotations = {
                summary     = "VMInsert pod {{ $labels.pod }} is down"
                description = "VMInsert pod {{ $labels.pod }} has been down for 2m. Metric ingestion is impaired."
              }
            },
          ]
        },
      ]
    }
  })
}

# --- VMRule: MongoDB alerting rules ---
# Depends on mongodb_scrape_enabled — no scrape = no metrics = no useful rules.
resource "kubectl_manifest" "vmrule_mongodb" {
  count = var.mongodb_scrape_enabled && var.vmalert_enabled ? 1 : 0

  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMRule"
    metadata = {
      name      = "mongodb-alerts"
      namespace = var.namespace
      labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "vmalert" })
    }
    spec = {
      groups = [
        {
          name = "mongodb"
          rules = [
            {
              alert = "MongoDBDown"
              expr  = "mongodb_up == 0"
              for   = "1m"
              labels = { severity = "critical", component = "mongodb" }
              annotations = {
                summary     = "MongoDB is unreachable on {{ $labels.pod }}"
                description = "mongodb_up=0 in namespace ${var.mongodb_exporter_namespace}. Check MongoDB pod and replica-set status."
              }
            },
            {
              alert = "MongoDBReplicationLagHigh"
              expr  = "mongodb_repl_lag_seconds > 10"
              for   = "2m"
              labels = { severity = "warning", component = "mongodb" }
              annotations = {
                summary     = "MongoDB replica lag is {{ $value | humanizeDuration }} on {{ $labels.member }}"
                description = "Replication lag exceeds 10s. Secondary may serve stale reads."
              }
            },
          ]
        }
      ]
    }
  })

  depends_on = [helm_release.vm_operator]
}

# --- VMRule: Kubernetes node and pod alerting rules ---
# Metrics come from node-exporter (node_*) and kube-state-metrics (kube_*)
# both scraped by VMAgent via selectAllByDefault=true.
resource "kubectl_manifest" "vmrule_kubernetes" {
  count = var.vmalert_enabled ? 1 : 0

  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMRule"
    metadata = {
      name      = "kubernetes-alerts"
      namespace = var.namespace
      labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "vmalert" })
    }
    spec = {
      groups = [
        {
          name = "kubernetes.nodes"
          rules = [
            {
              alert = "NodeNotReady"
              expr  = "kube_node_status_condition{condition=\"Ready\",status=\"true\"} == 0"
              for   = "5m"
              labels = { severity = "critical", component = "node" }
              annotations = {
                summary     = "Node {{ $labels.node }} is not ready"
                description = "Node {{ $labels.node }} has been NotReady for 5m. Pods may be evicted."
              }
            },
          ]
        },
        {
          name = "kubernetes.pods"
          rules = [
            {
              alert = "PodCrashLooping"
              expr  = "rate(kube_pod_container_status_restarts_total[15m]) * 60 > 0"
              for   = "5m"
              labels = { severity = "warning", component = "pod" }
              annotations = {
                summary     = "Pod {{ $labels.namespace }}/{{ $labels.pod }} is crash-looping"
                description = "Container {{ $labels.container }} restarting {{ $value | humanize }} times/min. Check pod logs."
              }
            },
          ]
        },
      ]
    }
  })

  depends_on = [helm_release.vm_operator]
}

# --- VMAlert: evaluates rules and sends alerts to Alertmanager ---
resource "kubectl_manifest" "vmalert" {
  count = var.vmalert_enabled ? 1 : 0

  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMAlert"
    metadata = {
      name      = "vmalert"
      namespace = var.namespace
      labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "vmalert" })
    }
    spec = {
      replicaCount = 2

      # Read data from vmselect — always use accountID=0 for single-tenant clusters
      datasource = {
        url = "${local.vmselect_url}/select/0/prometheus"
      }

      # Send alerts to Alertmanager if URL is provided
      notifiers = var.alertmanager_url != "" ? [
        { url = var.alertmanager_url }
      ] : []

      # Remote read for evaluating rules that span restart boundaries
      remoteRead = {
        url = "${local.vmselect_url}/select/0/prometheus"
      }

      # Write recording rule results back into VMCluster
      remoteWrite = {
        url = "${local.vminsert_url}/insert/0/prometheus"
      }

      # Watch VMRule CRDs in this namespace
      ruleSelector = {
        matchLabels = local.common_labels
      }

      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { cpu = "200m", memory = "256Mi" }
      }

      podDisruptionBudget = {
        minAvailable = 1
      }

      serviceAccountName = kubernetes_service_account.vmalert[0].metadata[0].name

      securityContext = {
        runAsNonRoot = true
        runAsUser    = 65534
      }

      nodeSelector = length(var.node_selector) > 0 ? var.node_selector : null
    }
  })

  depends_on = [
    kubectl_manifest.vmcluster,
    kubectl_manifest.vmrule_victoriametrics,
    kubectl_manifest.vmrule_mongodb,
    kubectl_manifest.vmrule_kubernetes,
    kubernetes_service_account.vmalert,
  ]
}
