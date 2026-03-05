# EBS gp3 StorageClass for vmstorage PVCs
# volumeBindingMode=WaitForFirstConsumer ensures the PV is provisioned in the
# same AZ as the pod — critical for zone-aware scheduling and performance.

resource "kubernetes_storage_class_v1" "vmstorage" {
  count = var.create_storage_class ? 1 : 0

  metadata {
    name = var.storage_class_name
    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "vmstorage"
    })
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true

  parameters = {
    type   = "gp3"
    fsType = "ext4"
    # gp3 provisioned IOPS (absolute, not per-GB — AWS EBS CSI driver requires this).
    # Valid range for gp3: 3000–16000. 6000 provides 2× the baseline for
    # vmstorage write-heavy workloads without incurring io2 pricing.
    iops       = "6000"
    throughput = "250"
  }

  lifecycle {
    # Ignore parameter changes after initial creation — changing provisioner
    # parameters doesn't affect existing PVs, only new ones.
    ignore_changes = [parameters]
  }
}
