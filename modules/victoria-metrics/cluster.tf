# VMCluster CRD — core HA cluster managed by VictoriaMetrics Operator
#
# Topology:
#   vmstorage  — StatefulSet, PVC-backed, receives writes from vminsert and
#                serves reads to vmselect via internal ports 8400/8401
#   vminsert   — Stateless Deployment, accepts remote-write on port 8480,
#                shards + replicates to vmstorage
#   vmselect   — Stateless Deployment, query frontend on port 8481,
#                de-duplicates replicated series for the client
#
# Replication:
#   replicationFactor=2  →  every series is written to 2 vmstorage nodes
#   dedup.minScrapeInterval=1ms on vmselect MUST be set when RF > 1
#   to de-duplicate identical samples before returning query results.

# Uses kubectl_manifest (gavinbunney/kubectl) because the VM Operator admission
# webhook defaults image, serviceAccountName, ports etc. after creation.
# hashicorp/kubernetes fails with "incorrect object attributes" for CRDs that
# use x-kubernetes-preserve-unknown-fields. kubectl + server_side_apply=true
# only tracks the fields we declare and safely ignores all server-side defaults.
resource "kubectl_manifest" "vmcluster" {
  force_conflicts   = true
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMCluster"
    metadata = {
      name      = var.vm_cluster_name
      namespace = var.namespace
      labels    = local.common_labels
    }
    spec = {
      retentionPeriod   = var.retention_period
      replicationFactor = var.replication_factor

      # -----------------------------------------------------------------------
      # vmstorage — persistent data store
      # -----------------------------------------------------------------------
      vmstorage = {
        replicaCount = var.vmstorage_replicas

        storage = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = local.effective_storage_class
              accessModes      = ["ReadWriteOnce"]
              resources = {
                requests = {
                  storage = var.vmstorage_storage_size
                }
              }
            }
          }
        }

        resources = {
          requests = {
            cpu    = local._norm_cpu.vs_req
            memory = var.vmstorage_resources.requests.memory
          }
          limits = {
            cpu    = local._norm_cpu.vs_lim
            memory = var.vmstorage_resources.limits.memory
          }
        }

        # Graceful shutdown handled automatically in v1.136.0+

        # PDB — tolerate losing 1 of 3 nodes; 2 must stay for RF=2 durability
        podDisruptionBudget = {
          minAvailable = 2
        }

        # Hard anti-affinity: never schedule two vmstorage pods on the same node
        affinity = {
          podAntiAffinity = {
            requiredDuringSchedulingIgnoredDuringExecution = [
              {
                topologyKey = "kubernetes.io/hostname"
                labelSelector = {
                  matchLabels = {
                    "app.kubernetes.io/name" = "vmstorage"
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
          fsGroup      = 65534
        }

        readinessProbe = {
          httpGet = {
            path = "/health"
            port = 8482
          }
          initialDelaySeconds = 10
          periodSeconds       = 10
          failureThreshold    = 3
        }

        livenessProbe = {
          httpGet = {
            path = "/health"
            port = 8482
          }
          initialDelaySeconds = 30
          periodSeconds       = 30
          failureThreshold    = 5
        }

        nodeSelector = length(var.node_selector) > 0 ? var.node_selector : null
        tolerations = [
          for t in var.tolerations : merge(
            { key = t.key, operator = t.operator },
            t.value != null ? { value = t.value } : {},
            t.effect != null ? { effect = t.effect } : {}
          )
        ]
      }

      # -----------------------------------------------------------------------
      # vminsert — stateless ingestion layer
      # -----------------------------------------------------------------------
      vminsert = {
        replicaCount = var.vminsert_replicas

        resources = {
          requests = {
            cpu    = local._norm_cpu.vi_req
            memory = var.vminsert_resources.requests.memory
          }
          limits = {
            cpu    = local._norm_cpu.vi_lim
            memory = var.vminsert_resources.limits.memory
          }
        }

        # HPA — scale on CPU and memory pressure (embedded in the CRD spec)
        hpa = {
          minReplicas = var.vminsert_min_replicas
          maxReplicas = var.vminsert_max_replicas
          metrics = [
            {
              type = "Resource"
              resource = {
                name = "cpu"
                target = {
                  type               = "Utilization"
                  averageUtilization = 70
                }
              }
            },
            {
              type = "Resource"
              resource = {
                name = "memory"
                target = {
                  type               = "Utilization"
                  averageUtilization = 80
                }
              }
            }
          ]
        }

        podDisruptionBudget = {
          minAvailable = 2
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
                      "app.kubernetes.io/name" = "vminsert"
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

        readinessProbe = {
          httpGet = {
            path = "/health"
            port = 8480
          }
          initialDelaySeconds = 5
          periodSeconds       = 10
          failureThreshold    = 3
        }

        livenessProbe = {
          httpGet = {
            path = "/health"
            port = 8480
          }
          initialDelaySeconds = 15
          periodSeconds       = 30
          failureThreshold    = 5
        }

        nodeSelector = length(var.node_selector) > 0 ? var.node_selector : null
        tolerations = [
          for t in var.tolerations : merge(
            { key = t.key, operator = t.operator },
            t.value != null ? { value = t.value } : {},
            t.effect != null ? { effect = t.effect } : {}
          )
        ]
      }

      # -----------------------------------------------------------------------
      # vmselect — stateless query layer
      # -----------------------------------------------------------------------
      vmselect = {
        replicaCount = var.vmselect_replicas

        # REQUIRED when replicationFactor > 1:
        # dedup.minScrapeInterval de-duplicates identical samples that were
        # replicated across multiple vmstorage nodes, preventing doubled series.
        # denyPartialResponse=false: return partial results rather than failing
        # when a vmstorage pod is temporarily unavailable.
        extraArgs = {
          "dedup.minScrapeInterval"     = "1ms"
          "search.denyPartialResponse"  = "false"
        }

        resources = {
          requests = {
            cpu    = local._norm_cpu.vsel_req
            memory = var.vmselect_resources.requests.memory
          }
          limits = {
            cpu    = local._norm_cpu.vsel_lim
            memory = var.vmselect_resources.limits.memory
          }
        }

        hpa = {
          minReplicas = var.vmselect_min_replicas
          maxReplicas = var.vmselect_max_replicas
          metrics = [
            {
              type = "Resource"
              resource = {
                name = "cpu"
                target = {
                  type               = "Utilization"
                  averageUtilization = 70
                }
              }
            },
            {
              type = "Resource"
              resource = {
                name = "memory"
                target = {
                  type               = "Utilization"
                  averageUtilization = 80
                }
              }
            }
          ]
        }

        podDisruptionBudget = {
          minAvailable = 2
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
                      "app.kubernetes.io/name" = "vmselect"
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
          fsGroup      = 65534
        }

        readinessProbe = {
          httpGet = {
            path = "/health"
            port = 8481
          }
          initialDelaySeconds = 5
          periodSeconds       = 10
          failureThreshold    = 3
        }

        livenessProbe = {
          httpGet = {
            path = "/health"
            port = 8481
          }
          initialDelaySeconds = 15
          periodSeconds       = 30
          failureThreshold    = 5
        }

        nodeSelector = length(var.node_selector) > 0 ? var.node_selector : null
        tolerations = [
          for t in var.tolerations : merge(
            { key = t.key, operator = t.operator },
            t.value != null ? { value = t.value } : {},
            t.effect != null ? { effect = t.effect } : {}
          )
        ]        
      }
    }
  })

  depends_on = [helm_release.vm_operator]
}
