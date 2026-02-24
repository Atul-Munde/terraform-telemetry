# otel-operator Module — Main Entry Point
# Installs the OpenTelemetry Operator via Helm.
# All collector CRDs, RBAC, and Instrumentation are managed by sub-files
# in this module (rbac.tf, collector-agent.tf, collector-gateway.tf, etc.)

locals {
  common_labels = merge({
    "app.kubernetes.io/part-of"   = "opentelemetry"
    "managed-by"                  = "terraform"
    "environment"                 = var.environment
  }, var.labels)

  # -------------------------------------------------------------------------
  # CPU normalization — the Kubernetes API server stores whole-CPU millicores
  # as integers: "2000m" → "2", "4000m" → "4".  The kubernetes_manifest
  # provider reads the stored value back and compares it against the planned
  # value.  If they differ, Terraform raises a "provider produced inconsistent
  # result" error on every apply.  Pre-apply the same normalization here so the
  # planned value always matches what the API server will store.
  #
  # Rule: "N000m" → "N"   (only exact multiples of 1000m, i.e. whole cores)
  #       anything else   → unchanged (e.g. "500m", "1500m")
  # -------------------------------------------------------------------------
  _norm_cpu = {
    gw_req    = can(regex("^([0-9]+)000m$", var.gateway_resources.requests.cpu))    ? tostring(tonumber(regex("^([0-9]+)000m$", var.gateway_resources.requests.cpu)[0]))    : var.gateway_resources.requests.cpu
    gw_lim    = can(regex("^([0-9]+)000m$", var.gateway_resources.limits.cpu))      ? tostring(tonumber(regex("^([0-9]+)000m$", var.gateway_resources.limits.cpu)[0]))      : var.gateway_resources.limits.cpu
    ag_req    = can(regex("^([0-9]+)000m$", var.agent_resources.requests.cpu))      ? tostring(tonumber(regex("^([0-9]+)000m$", var.agent_resources.requests.cpu)[0]))      : var.agent_resources.requests.cpu
    ag_lim    = can(regex("^([0-9]+)000m$", var.agent_resources.limits.cpu))        ? tostring(tonumber(regex("^([0-9]+)000m$", var.agent_resources.limits.cpu)[0]))        : var.agent_resources.limits.cpu
    im_req    = can(regex("^([0-9]+)000m$", var.infra_metrics_resources.requests.cpu)) ? tostring(tonumber(regex("^([0-9]+)000m$", var.infra_metrics_resources.requests.cpu)[0])) : var.infra_metrics_resources.requests.cpu
    im_lim    = can(regex("^([0-9]+)000m$", var.infra_metrics_resources.limits.cpu))   ? tostring(tonumber(regex("^([0-9]+)000m$", var.infra_metrics_resources.limits.cpu)[0]))   : var.infra_metrics_resources.limits.cpu
  }
}

# -----------------------------------------------------------------------
# OpenTelemetry Operator — Helm Release
# replicaCount: 2  = HA (leader election built-in)
# certManager: true = required for webhook TLS (cert-manager must be installed)
# -----------------------------------------------------------------------
resource "helm_release" "otel_operator" {
  name             = "opentelemetry-operator"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-operator"
  version          = var.operator_chart_version
  namespace        = var.operator_namespace
  create_namespace = true  # opentelemetry-operator-system is the Helm chart default
  timeout          = 300
  wait             = true
  wait_for_jobs    = true

  values = [
    templatefile("${path.module}/templates/operator-values.yaml.tpl", {
      operator_replicas              = var.operator_replicas
      operator_image_tag             = var.operator_image_tag
      nodejs_image_repository        = split(":", var.nodejs_instrumentation_image)[0]
      nodejs_image_tag               = split(":", var.nodejs_instrumentation_image)[1]
      operator_resources_requests_cpu    = var.operator_resources.requests.cpu
      operator_resources_requests_memory = var.operator_resources.requests.memory
      operator_resources_limits_cpu      = var.operator_resources.limits.cpu
      operator_resources_limits_memory   = var.operator_resources.limits.memory
      node_selector                  = var.node_selector
    })
  ]
}
