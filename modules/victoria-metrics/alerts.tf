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
            # vmstorage pod unavailable
            {
              alert = "VMStorageDown"
              expr  = "up{job=\"vmstorage\"} == 0"
              for   = "2m"
              labels = {
                severity  = "critical"
                component = "vmstorage"
              }
              annotations = {
                summary     = "VictoriaMetrics storage node {{ $labels.pod }} is down"
                description = "VMStorage pod {{ $labels.pod }} in namespace {{ $labels.namespace }} has been down for more than 2 minutes. This may cause data loss if replication factor is insufficient."
                runbook     = "https://docs.victoriametrics.com/cluster-victoriametrics/#vmstorage"
              }
            },
            # vminsert pod unavailable
            {
              alert = "VMInsertDown"
              expr  = "up{job=\"vminsert\"} == 0"
              for   = "2m"
              labels = {
                severity  = "critical"
                component = "vminsert"
              }
              annotations = {
                summary     = "VictoriaMetrics insert node {{ $labels.pod }} is down"
                description = "VMInsert pod {{ $labels.pod }} in namespace {{ $labels.namespace }} has been down for more than 2 minutes. Metric ingestion may be impaired."
                runbook     = "https://docs.victoriametrics.com/cluster-victoriametrics/#vminsert"
              }
            },
            # vmselect pod unavailable
            {
              alert = "VMSelectDown"
              expr  = "up{job=\"vmselect\"} == 0"
              for   = "2m"
              labels = {
                severity  = "warning"
                component = "vmselect"
              }
              annotations = {
                summary     = "VictoriaMetrics select node {{ $labels.pod }} is down"
                description = "VMSelect pod {{ $labels.pod }} in namespace {{ $labels.namespace }} has been down for more than 2 minutes. Query availability may be reduced."
                runbook     = "https://docs.victoriametrics.com/cluster-victoriametrics/#vmselect"
              }
            },
            # vmstorage disk near full — below 15% free triggers warning, below 5% critical
            # vm_data_size_bytes is the stored data size, NOT the total disk.
            # Approximate free% as: free / (free + data). This is conservative
            # (ignores OS/filesystem overhead) but avoids false positives.
            {
              alert = "VMStorageDiskFull"
              expr  = "(vm_free_disk_space_bytes{job=\"vmstorage\"} / (vm_free_disk_space_bytes{job=\"vmstorage\"} + vm_data_size_bytes{job=\"vmstorage\"})) < 0.15"
              for   = "5m"
              labels = {
                severity  = "warning"
                component = "vmstorage"
              }
              annotations = {
                summary     = "VictoriaMetrics storage disk is running low on {{ $labels.pod }}"
                description = "VMStorage pod {{ $labels.pod }} has less than 15% free disk space. Current free ratio: {{ $value | humanizePercentage }}. Expand the PVC or reduce retention period."
                runbook     = "https://docs.victoriametrics.com/cluster-victoriametrics/#vmstorage"
              }
            },
            {
              alert = "VMStorageDiskCritical"
              expr  = "(vm_free_disk_space_bytes{job=\"vmstorage\"} / (vm_free_disk_space_bytes{job=\"vmstorage\"} + vm_data_size_bytes{job=\"vmstorage\"})) < 0.05"
              for   = "2m"
              labels = {
                severity  = "critical"
                component = "vmstorage"
              }
              annotations = {
                summary     = "VictoriaMetrics storage disk is critically full on {{ $labels.pod }}"
                description = "VMStorage pod {{ $labels.pod }} has less than 5% free disk space. Immediate action required to prevent data loss."
                runbook     = "https://docs.victoriametrics.com/cluster-victoriametrics/#vmstorage"
              }
            },
            # High ingestion rate — more than 1M samples/sec across the cluster
            {
              alert = "VMHighIngestionRate"
              expr  = "sum(rate(vm_rows_inserted_total{job=\"vminsert\"}[5m])) > 1000000"
              for   = "10m"
              labels = {
                severity  = "warning"
                component = "vminsert"
              }
              annotations = {
                summary     = "VictoriaMetrics ingestion rate is very high"
                description = "The cluster is ingesting more than 1 million samples/second (current: {{ $value | humanize }} rows/s). Consider scaling up vminsert and vmstorage replicas."
                runbook     = "https://docs.victoriametrics.com/cluster-victoriametrics/"
              }
            },
            # Replication health — any vmstorage unavailable means effective replication is < configured factor
            {
              alert = "VMStorageReplicationFactorLow"
              expr  = "count(up{job=\"vmstorage\"} == 1) < ${var.vmstorage_replicas}"
              for   = "5m"
              labels = {
                severity  = "warning"
                component = "vmstorage"
              }
              annotations = {
                summary     = "VictoriaMetrics replication factor is below the configured value"
                description = "Only {{ $value }} of ${var.vmstorage_replicas} vmstorage pods are healthy. Effective replication factor is degraded. Data durability may be reduced."
                runbook     = "https://docs.victoriametrics.com/cluster-victoriametrics/#replication-and-data-safety"
              }
            },
            # Too many insert errors
            {
              alert = "VMInsertHighErrorRate"
              expr  = "sum(rate(vm_http_errors_total{job=\"vminsert\"}[5m])) / sum(rate(vm_http_requests_total{job=\"vminsert\"}[5m])) > 0.05"
              for   = "5m"
              labels = {
                severity  = "warning"
                component = "vminsert"
              }
              annotations = {
                summary     = "VictoriaMetrics vminsert has a high error rate"
                description = "More than 5% of vminsert HTTP requests are failing (current: {{ $value | humanizePercentage }}). Check vminsert pod logs."
                runbook     = "https://docs.victoriametrics.com/cluster-victoriametrics/#vminsert"
              }
            },
          ]
        },
        {
          name = "victoriametrics.operator"
          rules = [
            # VictoriaMetrics operator pod unavailable
            {
              alert = "VMOperatorDown"
              expr  = "up{job=\"victoriametrics-operator\"} == 0"
              for   = "5m"
              labels = {
                severity  = "critical"
                component = "operator"
              }
              annotations = {
                summary     = "VictoriaMetrics Operator is down"
                description = "The VictoriaMetrics Operator pod in namespace {{ $labels.namespace }} has been down for more than 5 minutes. CRD reconciliation is stopped."
                runbook     = "https://docs.victoriametrics.com/operator/"
              }
            },
          ]
        },
      ]
    }
  })
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
        url = "${local.vminsert_url}/insert/0/prometheus/api/v1/write"
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
    kubernetes_service_account.vmalert,
  ]
}
