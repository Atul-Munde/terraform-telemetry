# NetworkPolicies for VictoriaMetrics components
# These enforce that only legitimate peers can reach each component.
# --
# Port reference:
#   vmstorage : 8400 (vminsert writes), 8401 (vmselect reads), 8482 (scraping / health)
#   vminsert  : 8480 (remote-write ingestion)
#   vmselect  : 8481 (query API)

# ---------------------------------------------------------------------------
# vmstorage NetworkPolicy
# Allow:
#   - vminsert  → vmstorage:8400 (insert path)
#   - vmselect  → vmstorage:8401 (select path)
#   - vmagent   → vmstorage:8482 (Prometheus scrape)
#   - kube-prometheus / Prometheus → vmstorage:8482 (scrape, optional)
#   - Egress: allow DNS (53) + all TCP (needed for gossip / snapshotting)
# ---------------------------------------------------------------------------
resource "kubernetes_manifest" "netpol_vmstorage" {
  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata = {
      name      = "vmstorage-netpol"
      namespace = var.namespace
      labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "vmstorage" })
    }
    spec = {
      podSelector = {
        matchLabels = {
          "app.kubernetes.io/name" = "vmstorage"
        }
      }
      policyTypes = ["Ingress", "Egress"]

      ingress = [
        # vminsert writes to vmstorage on port 8400
        {
          from = [
            {
              podSelector = {
                matchLabels = {
                  "app.kubernetes.io/name" = "vminsert"
                }
              }
            }
          ]
          ports = [{ port = 8400, protocol = "TCP" }]
        },
        # vmselect reads from vmstorage on port 8401
        {
          from = [
            {
              podSelector = {
                matchLabels = {
                  "app.kubernetes.io/name" = "vmselect"
                }
              }
            }
          ]
          ports = [{ port = 8401, protocol = "TCP" }]
        },
        # vmagent/Prometheus scraping on port 8482 (health also uses 8482)
        {
          from = [
            {
              podSelector = {
                matchLabels = { "app.kubernetes.io/name" = "vmagent" }
              }
            },
            # Allow kube-prometheus Prometheus server to scrape
            {
              namespaceSelector = {
                matchLabels = { "kubernetes.io/metadata.name" = var.namespace }
              }
              podSelector = {
                matchLabels = { "app.kubernetes.io/name" = "prometheus" }
              }
            }
          ]
          ports = [{ port = 8482, protocol = "TCP" }]
        },
      ]

      egress = [
        # DNS resolution
        {
          ports = [{ port = 53, protocol = "UDP" }, { port = 53, protocol = "TCP" }]
        },
        # Allow all TCP egress (vmstorage needs outbound for cluster-internal traffic / snapshotting)
        {
          ports = [{ port = 1, endPort = 65535, protocol = "TCP" }]
        },
      ]
    }
  }

  depends_on = [kubectl_manifest.vmcluster]
}

# ---------------------------------------------------------------------------
# vminsert NetworkPolicy
# Allow:
#   - Any pod in the telemetry namespace → vminsert:8480 (remote-write)
#   - VMAuth proxy → vminsert:8480
#   - vmagent (scrape) → vminsert:8482 is not a real port for vminsert; scrape comes via VMServiceScrape
# ---------------------------------------------------------------------------
resource "kubernetes_manifest" "netpol_vminsert" {
  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata = {
      name      = "vminsert-netpol"
      namespace = var.namespace
      labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "vminsert" })
    }
    spec = {
      podSelector = {
        matchLabels = {
          "app.kubernetes.io/name" = "vminsert"
        }
      }
      policyTypes = ["Ingress", "Egress"]

      ingress = [
        # Accept remote-write on 8480 from any pod within the telemetry namespace
        {
          from = [
            {
              namespaceSelector = {
                matchLabels = { "kubernetes.io/metadata.name" = var.namespace }
              }
            }
          ]
          ports = [{ port = 8480, protocol = "TCP" }]
        },
        # Also accept from any namespace that has the otel-collector forwarding metrics
        # (covers the otel-collector module sending OTLP metrics to vminsert)
        {
          from = [
            {
              namespaceSelector = {}
              podSelector = {
                matchLabels = { "app.kubernetes.io/component" = "otel-collector" }
              }
            }
          ]
          ports = [{ port = 8480, protocol = "TCP" }]
        },
      ]

      egress = [
        # DNS
        {
          ports = [{ port = 53, protocol = "UDP" }, { port = 53, protocol = "TCP" }]
        },
        # Allow outbound to vmstorage (ports 8400)
        {
          to = [
            {
              podSelector = {
                matchLabels = {
                  "app.kubernetes.io/name" = "vmstorage"
                }
              }
            }
          ]
          ports = [{ port = 8400, protocol = "TCP" }]
        },
      ]
    }
  }

  depends_on = [kubectl_manifest.vmcluster]
}

# ---------------------------------------------------------------------------
# vmselect NetworkPolicy
# Allow:
#   - VMAuth proxy → vmselect:8481
#   - vmagent → vmselect:8481 (health / /health endpoint)
#   - Grafana (label-selected) → vmselect:8481
#   - Any pod in telemetry ns → vmselect:8481 (permissive for internal tools)
# ---------------------------------------------------------------------------
resource "kubernetes_manifest" "netpol_vmselect" {
  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata = {
      name      = "vmselect-netpol"
      namespace = var.namespace
      labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "vmselect" })
    }
    spec = {
      podSelector = {
        matchLabels = {
          "app.kubernetes.io/name" = "vmselect"
        }
      }
      policyTypes = ["Ingress", "Egress"]

      ingress = [
        # Accept queries on 8481 from within the telemetry namespace (VMAlert, Grafana, etc.)
        {
          from = [
            {
              namespaceSelector = {
                matchLabels = { "kubernetes.io/metadata.name" = var.namespace }
              }
            }
          ]
          ports = [{ port = 8481, protocol = "TCP" }]
        },
        # Accept queries from Grafana regardless of namespace
        {
          from = [
            {
              namespaceSelector = {}
              podSelector = {
                matchLabels = { "app.kubernetes.io/name" = "grafana" }
              }
            }
          ]
          ports = [{ port = 8481, protocol = "TCP" }]
        },
        # VMAuth proxy forward
        {
          from = [
            {
              podSelector = {
                matchLabels = { "app.kubernetes.io/name" = "vmauth" }
              }
            }
          ]
          ports = [{ port = 8481, protocol = "TCP" }]
        },
      ]

      egress = [
        # DNS
        {
          ports = [{ port = 53, protocol = "UDP" }, { port = 53, protocol = "TCP" }]
        },
        # Allow outbound to vmstorage (port 8401 for select path)
        {
          to = [
            {
              podSelector = {
                matchLabels = {
                  "app.kubernetes.io/name" = "vmstorage"
                }
              }
            }
          ]
          ports = [{ port = 8401, protocol = "TCP" }]
        },
      ]
    }
  }

  depends_on = [kubectl_manifest.vmcluster]
}
