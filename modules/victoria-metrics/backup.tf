# Scheduled backup of VictoriaMetrics vmstorage data to S3
# Only deployed when backup_enabled = true.
#
# Strategy:
#   vmbackup requires access to the local data directory, so we exec into each
#   vmstorage pod using kubectl and run vmbackup there. A CronJob with a
#   kubectl image iterates over all vmstorage pods (0..N-1) and executes
#   vmbackup with -snapshot.createURL so it atomically snapshots then uploads.
#
# IRSA for the vmbackup Kubernetes ServiceAccount is wired in s3.tf; this file
# adds the RBAC needed for the CronJob pod to exec into vmstorage pods.

# ---------------------------------------------------------------------------
# RBAC — allow vmbackup service account to exec into vmstorage pods
# ---------------------------------------------------------------------------
resource "kubernetes_role" "vmbackup_exec" {
  count = var.backup_enabled ? 1 : 0

  metadata {
    name      = "vmbackup-exec"
    namespace = var.namespace
    labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "vmbackup" })
  }

  rule {
    api_groups = [""]
    resources  = ["pods/exec"]
    verbs      = ["create"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_role_binding" "vmbackup_exec" {
  count = var.backup_enabled ? 1 : 0

  metadata {
    name      = "vmbackup-exec"
    namespace = var.namespace
    labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "vmbackup" })
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.vmbackup_exec[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = var.backup_enabled ? kubernetes_service_account.vmbackup[0].metadata[0].name : "vmbackup"
    namespace = var.namespace
  }
}

# ---------------------------------------------------------------------------
# CronJob — iterates over all vmstorage pods and triggers vmbackup
# ---------------------------------------------------------------------------
resource "kubernetes_manifest" "vmbackup_cronjob" {
  count = var.backup_enabled ? 1 : 0

  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "batch/v1"
    kind       = "CronJob"
    metadata = {
      name      = "vmbackup"
      namespace = var.namespace
      labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "vmbackup" })
    }
    spec = {
      schedule          = var.backup_schedule
      concurrencyPolicy = "Forbid"

      # Retain last 3 successful and 1 failed job for debugging
      successfulJobsHistoryLimit = 3
      failedJobsHistoryLimit     = 1

      jobTemplate = {
        spec = {
          template = {
            metadata = {
              labels = merge(local.common_labels, { "app.kubernetes.io/component" = "vmbackup" })
            }
            spec = {
              restartPolicy      = "OnFailure"
              serviceAccountName = kubernetes_service_account.vmbackup[0].metadata[0].name

              # IRSA requires host-network=false and the projected token volume the SA annotation handles
              automountServiceAccountToken = true

              securityContext = {
                runAsNonRoot = true
                runAsUser    = 65534
                runAsGroup   = 65534
              }

              containers = [
                {
                  name  = "vmbackup"
                  # Use bitnami/kubectl which has both kubectl and a shell available
                  # vmbackup itself is executed via kubectl exec inside each vmstorage pod
                  image = "bitnami/kubectl:1.29"

                  command = ["/bin/sh", "-c"]
                  args = [
                    <<-SCRIPT
                    set -euo pipefail
                    NAMESPACE="${var.namespace}"
                    CLUSTER="${var.vm_cluster_name}"
                    REPLICAS=${var.vmstorage_replicas}
                    S3_BUCKET="${local.s3_bucket_name}"
                    S3_REGION="${var.backup_s3_region}"
                    DATE=$(date +%Y%m%d-%H%M%S)

                    echo "Starting VictoriaMetrics backup for cluster $CLUSTER at $DATE"

                    for i in $(seq 0 $((REPLICAS - 1))); do
                      POD="vmstorage-$CLUSTER-$i"
                      DST="s3://$S3_BUCKET/backups/$DATE/$POD"
                      echo "Backing up $POD → $DST"

                      kubectl exec -n "$NAMESPACE" "$POD" -- \
                        /app/vmbackup \
                          -storageDataPath=/storage \
                          -snapshot.createURL="http://localhost:8482/snapshot/create" \
                          -dst="$DST" \
                          -s3.region="$S3_REGION" \
                        && echo "$POD backup completed successfully" \
                        || { echo "ERROR: backup failed for $POD"; exit 1; }
                    done

                    echo "All vmstorage backups completed for $DATE"
                    SCRIPT
                  ]

                  resources = {
                    requests = { cpu = "50m", memory = "64Mi" }
                    limits   = { cpu = "200m", memory = "128Mi" }
                  }

                  env = [
                    {
                      name  = "AWS_DEFAULT_REGION"
                      value = var.backup_s3_region
                    },
                    # IRSA injects AWS_ROLE_ARN and AWS_WEB_IDENTITY_TOKEN_FILE automatically
                    # via the pod's projected service account token — no explicit env needed.
                  ]
                }
              ]

              nodeSelector = length(var.node_selector) > 0 ? var.node_selector : null
              tolerations  = [
                for t in var.tolerations : merge(
                  { key = t.key, operator = t.operator },
                  t.value  != null ? { value  = t.value }  : {},
                  t.effect != null ? { effect = t.effect }  : {}
                )
              ]
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubectl_manifest.vmcluster,
    kubernetes_service_account.vmbackup,
    kubernetes_role_binding.vmbackup_exec,
  ]
}
