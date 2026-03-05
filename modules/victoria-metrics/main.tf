# victoria-metrics Module — Main Entry Point
# Installs the VictoriaMetrics Operator via Helm.
# VMCluster, VMAgent, VMAlert, VMAuth, and related CRDs are managed in sub-files.

locals {
  common_labels = merge({
    "app.kubernetes.io/part-of" = "victoria-metrics"
    "managed-by"                = "terraform"
    "environment"               = var.environment
  }, var.labels)

  # ALB annotations — internet-facing, HTTPS-only, IP target mode.
  alb_annotations = merge(
    {
      "alb.ingress.kubernetes.io/scheme"                       = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"                  = "ip"
      "alb.ingress.kubernetes.io/certificate-arn"              = var.alb_certificate_arn
      "alb.ingress.kubernetes.io/listen-ports"                 = "[{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"                 = "443"
      "alb.ingress.kubernetes.io/healthcheck-path"             = "/health"
      "alb.ingress.kubernetes.io/healthcheck-interval-seconds" = "15"
      "alb.ingress.kubernetes.io/healthcheck-timeout-seconds"  = "5"
      "alb.ingress.kubernetes.io/healthy-threshold-count"      = "2"
      "alb.ingress.kubernetes.io/unhealthy-threshold-count"    = "3"
    },
    var.alb_group_name != "" ? {
      "alb.ingress.kubernetes.io/group.name" = var.alb_group_name
    } : {}
  )

  # -------------------------------------------------------------------------
  # CPU normalisation — the Kubernetes API server normalises whole-CPU millicores
  # to integer form: "1000m" → "1", "2000m" → "2". Without this, the
  # kubernetes_manifest provider raises "provider produced inconsistent result"
  # errors because the planned value doesn't match the stored value.
  #
  # Rule: "<N>000m" (exact multiples of 1000) → "<N>"
  #       anything else (e.g. "500m", "1500m") → unchanged
  # -------------------------------------------------------------------------
  _norm_cpu = {
    vs_req   = can(regex("^([0-9]+)000m$", var.vmstorage_resources.requests.cpu)) ? tostring(tonumber(regex("^([0-9]+)000m$", var.vmstorage_resources.requests.cpu)[0])) : var.vmstorage_resources.requests.cpu
    vs_lim   = can(regex("^([0-9]+)000m$", var.vmstorage_resources.limits.cpu))   ? tostring(tonumber(regex("^([0-9]+)000m$", var.vmstorage_resources.limits.cpu)[0]))   : var.vmstorage_resources.limits.cpu
    vi_req   = can(regex("^([0-9]+)000m$", var.vminsert_resources.requests.cpu))  ? tostring(tonumber(regex("^([0-9]+)000m$", var.vminsert_resources.requests.cpu)[0]))  : var.vminsert_resources.requests.cpu
    vi_lim   = can(regex("^([0-9]+)000m$", var.vminsert_resources.limits.cpu))    ? tostring(tonumber(regex("^([0-9]+)000m$", var.vminsert_resources.limits.cpu)[0]))    : var.vminsert_resources.limits.cpu
    vsel_req = can(regex("^([0-9]+)000m$", var.vmselect_resources.requests.cpu))  ? tostring(tonumber(regex("^([0-9]+)000m$", var.vmselect_resources.requests.cpu)[0]))  : var.vmselect_resources.requests.cpu
    vsel_lim = can(regex("^([0-9]+)000m$", var.vmselect_resources.limits.cpu))    ? tostring(tonumber(regex("^([0-9]+)000m$", var.vmselect_resources.limits.cpu)[0]))    : var.vmselect_resources.limits.cpu
    va_req   = can(regex("^([0-9]+)000m$", var.vmagent_resources.requests.cpu))   ? tostring(tonumber(regex("^([0-9]+)000m$", var.vmagent_resources.requests.cpu)[0]))   : var.vmagent_resources.requests.cpu
    va_lim   = can(regex("^([0-9]+)000m$", var.vmagent_resources.limits.cpu))     ? tostring(tonumber(regex("^([0-9]+)000m$", var.vmagent_resources.limits.cpu)[0]))     : var.vmagent_resources.limits.cpu
  }

  # Derived service name prefixes (operator convention: <component>-<clusterName>)
  vminsert_svc  = "vminsert-${var.vm_cluster_name}"
  vmselect_svc  = "vmselect-${var.vm_cluster_name}"
  vmstorage_svc = "vmstorage-${var.vm_cluster_name}"

  # Internal ClusterIP URLs
  vminsert_url  = "http://${local.vminsert_svc}.${var.namespace}.svc.cluster.local:8480"
  vmselect_url  = "http://${local.vmselect_svc}.${var.namespace}.svc.cluster.local:8481"

  # Auto-generate S3 bucket name when not provided
  s3_bucket_name = var.backup_s3_bucket_name != "" ? var.backup_s3_bucket_name : "vm-backup-${var.environment}"

  # Storage class name: use the one created by this module or the provided name
  effective_storage_class = var.storage_class_name
}

# ---------------------------------------------------------------------------
# VictoriaMetrics Operator — Helm Release
# HA: replicaCount=2 when environment=production (leader-election built-in)
# ---------------------------------------------------------------------------
resource "helm_release" "vm_operator" {
  name             = "victoria-metrics-operator"
  repository       = "https://victoriametrics.github.io/helm-charts/"
  chart            = "victoria-metrics-operator"
  version          = var.vm_operator_chart_version
  namespace        = var.vm_operator_namespace
  create_namespace = true
  timeout          = 300
  wait             = true
  wait_for_jobs    = true

  values = [
    templatefile("${path.module}/templates/operator-values.yaml.tpl", {
      operator_replicas                  = var.environment == "production" ? 2 : var.vm_operator_replicas
      watch_namespace                    = var.namespace
      operator_resources_requests_cpu    = var.vm_operator_resources.requests.cpu
      operator_resources_requests_memory = var.vm_operator_resources.requests.memory
      operator_resources_limits_cpu      = var.vm_operator_resources.limits.cpu
      operator_resources_limits_memory   = var.vm_operator_resources.limits.memory
      node_selector                      = var.node_selector
    })
  ]
}
