# =============================================================================
# HA Elasticsearch Cluster — Dedicated Node Roles
# 3 Helm releases: master, data, coordinating
# =============================================================================

locals {
  cluster_name = var.cluster_name

  # Heap calculation helper — 50% of memory limit, capped at 31g (ES compressed oops threshold)
  calc_heap = { for role in ["master", "data", "coordinating"] :
    role => "${min(
      floor(
        tonumber(regex("([0-9]+)", var.node_roles[role].resources.limits.memory)[0]) *
        (can(regex("Gi", var.node_roles[role].resources.limits.memory)) ? 1024 : 1) * 0.5
      ),
      31744
    )}m"
  }

  xpack_security_enabled = var.elastic_password != ""
  elastic_secret_name    = local.xpack_security_enabled ? "elasticsearch-credentials" : ""

  # Coordinating endpoint — all consumers should connect here
  coordinating_endpoint = "${local.cluster_name}-coordinating.${var.namespace}.svc.cluster.local:9200"
}

# ---------------------------------------------------------------------------
# Credentials secret — shared across all node groups
# ---------------------------------------------------------------------------
resource "kubernetes_secret" "elasticsearch_credentials" {
  count = local.xpack_security_enabled ? 1 : 0

  metadata {
    name      = "elasticsearch-credentials"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "elasticsearch"
      "app.kubernetes.io/component"  = "credentials"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  type = "Opaque"

  data = {
    username         = "elastic"
    ELASTIC_PASSWORD = var.elastic_password
  }
}

# ---------------------------------------------------------------------------
# Shared Transport CA — one CA signed by Terraform, used by all node groups
# This ensures coordinating/data/master all trust each other's transport certs.
# Without this, each helm_release generates its own CA → PKIX mismatch.
# ---------------------------------------------------------------------------
resource "tls_private_key" "elasticsearch_ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "elasticsearch_ca" {
  private_key_pem   = tls_private_key.elasticsearch_ca.private_key_pem
  is_ca_certificate = true

  subject {
    common_name = "elasticsearch-ca"
  }

  validity_period_hours = 87600 # 10 years

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
  ]
}

# Per-role SANs covering service, headless, and localhost
locals {
  node_san_dns = {
    master = concat(
      [
        "${local.cluster_name}-master",
        "${local.cluster_name}-master.${var.namespace}",
        "${local.cluster_name}-master.${var.namespace}.svc",
        "${local.cluster_name}-master.${var.namespace}.svc.cluster.local",
        "${local.cluster_name}-master-headless",
        "${local.cluster_name}-master-headless.${var.namespace}",
        "${local.cluster_name}-master-headless.${var.namespace}.svc",
        "localhost",
      ],
      [for i in range(var.node_roles.master.replicas) :
        "${local.cluster_name}-master-${i}.${local.cluster_name}-master-headless.${var.namespace}.svc.cluster.local"
      ]
    )
    data = concat(
      [
        "${local.cluster_name}-data",
        "${local.cluster_name}-data.${var.namespace}",
        "${local.cluster_name}-data.${var.namespace}.svc",
        "${local.cluster_name}-data.${var.namespace}.svc.cluster.local",
        "${local.cluster_name}-data-headless",
        "${local.cluster_name}-data-headless.${var.namespace}",
        "${local.cluster_name}-data-headless.${var.namespace}.svc",
        "localhost",
      ],
      [for i in range(var.node_roles.data.replicas) :
        "${local.cluster_name}-data-${i}.${local.cluster_name}-data-headless.${var.namespace}.svc.cluster.local"
      ]
    )
    coordinating = concat(
      [
        "${local.cluster_name}-coordinating",
        "${local.cluster_name}-coordinating.${var.namespace}",
        "${local.cluster_name}-coordinating.${var.namespace}.svc",
        "${local.cluster_name}-coordinating.${var.namespace}.svc.cluster.local",
        "${local.cluster_name}-coordinating-headless",
        "${local.cluster_name}-coordinating-headless.${var.namespace}",
        "${local.cluster_name}-coordinating-headless.${var.namespace}.svc",
        "localhost",
      ],
      [for i in range(var.node_roles.coordinating.replicas) :
        "${local.cluster_name}-coordinating-${i}.${local.cluster_name}-coordinating-headless.${var.namespace}.svc.cluster.local"
      ]
    )
  }
}

resource "tls_private_key" "elasticsearch_node" {
  for_each  = toset(["master", "data", "coordinating"])
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "elasticsearch_node" {
  for_each        = toset(["master", "data", "coordinating"])
  private_key_pem = tls_private_key.elasticsearch_node[each.key].private_key_pem

  subject {
    common_name = "${local.cluster_name}-${each.key}"
  }

  dns_names    = local.node_san_dns[each.key]
  ip_addresses = ["127.0.0.1"]
}

resource "tls_locally_signed_cert" "elasticsearch_node" {
  for_each              = toset(["master", "data", "coordinating"])
  cert_request_pem      = tls_cert_request.elasticsearch_node[each.key].cert_request_pem
  ca_private_key_pem    = tls_private_key.elasticsearch_ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.elasticsearch_ca.cert_pem
  validity_period_hours = 87600

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
    "client_auth",
  ]
}

# One secret per node group — mounted explicitly via secretMounts in Helm values
resource "kubernetes_secret" "elasticsearch_transport_certs" {
  for_each = toset(["master", "data", "coordinating"])

  metadata {
    name      = "${local.cluster_name}-${each.key}-transport-certs"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "elasticsearch"
      "app.kubernetes.io/component"  = "transport-certs"
      "app.kubernetes.io/managed-by" = "terraform"
    }
    annotations = {
      # Force secret update when CA or node cert changes
      "terraform-ca-fingerprint"   = sha256(tls_self_signed_cert.elasticsearch_ca.cert_pem)
      "terraform-cert-fingerprint" = sha256(tls_locally_signed_cert.elasticsearch_node[each.key].cert_pem)
    }
  }

  type = "kubernetes.io/tls"

  data = {
    "ca.crt"  = tls_self_signed_cert.elasticsearch_ca.cert_pem
    "tls.crt" = tls_locally_signed_cert.elasticsearch_node[each.key].cert_pem
    "tls.key" = tls_private_key.elasticsearch_node[each.key].private_key_pem
  }
}

# ---------------------------------------------------------------------------
# Master Nodes — cluster state, shard allocation
# ---------------------------------------------------------------------------
resource "helm_release" "elasticsearch_master" {
  name             = "${local.cluster_name}-master"
  repository       = "https://helm.elastic.co"
  chart            = "elasticsearch"
  version          = "8.5.1"
  namespace        = var.namespace
  create_namespace = false
  timeout          = 600

  values = [
    templatefile("${path.module}/templates/master-values.yaml.tpl", {
      cluster_name              = local.cluster_name
      replicas                  = var.node_roles.master.replicas
      minimum_master_nodes      = floor(var.node_roles.master.replicas / 2) + 1
      resources_requests_cpu    = var.node_roles.master.resources.requests.cpu
      resources_requests_memory = var.node_roles.master.resources.requests.memory
      resources_limits_cpu      = var.node_roles.master.resources.limits.cpu
      resources_limits_memory   = var.node_roles.master.resources.limits.memory
      heap_size                 = local.calc_heap["master"]
      storage_class             = var.storage_class
      storage_size              = var.node_roles.master.storage_size
      node_selector             = var.node_selector
      tolerations               = var.tolerations
      anti_affinity             = var.anti_affinity
      xpack_security_enabled         = local.xpack_security_enabled
      elastic_secret_name            = local.elastic_secret_name
      elastic_password               = var.elastic_password
      transport_cert_secret_name     = kubernetes_secret.elasticsearch_transport_certs["master"].metadata[0].name
    })
  ]

  # Protect PVCs + data from accidental terraform destroy
  lifecycle {
    prevent_destroy = true
  }

  depends_on = [
    kubernetes_secret.elasticsearch_credentials,
  ]
}

# ---------------------------------------------------------------------------
# Data + Ingest Nodes — indexing, search, aggregations
# ---------------------------------------------------------------------------
resource "helm_release" "elasticsearch_data" {
  name             = "${local.cluster_name}-data"
  repository       = "https://helm.elastic.co"
  chart            = "elasticsearch"
  version          = "8.5.1"
  namespace        = var.namespace
  create_namespace = false
  timeout          = 600

  values = [
    templatefile("${path.module}/templates/data-values.yaml.tpl", {
      cluster_name              = local.cluster_name
      replicas                  = var.node_roles.data.replicas
      master_replicas           = var.node_roles.master.replicas
      resources_requests_cpu    = var.node_roles.data.resources.requests.cpu
      resources_requests_memory = var.node_roles.data.resources.requests.memory
      resources_limits_cpu      = var.node_roles.data.resources.limits.cpu
      resources_limits_memory   = var.node_roles.data.resources.limits.memory
      heap_size                 = local.calc_heap["data"]
      storage_class             = var.storage_class
      storage_size              = var.node_roles.data.storage_size
      node_selector             = var.node_selector
      tolerations               = var.tolerations
      anti_affinity             = var.anti_affinity
      xpack_security_enabled         = local.xpack_security_enabled
      elastic_secret_name            = local.elastic_secret_name
      elastic_password               = var.elastic_password
      transport_cert_secret_name     = kubernetes_secret.elasticsearch_transport_certs["data"].metadata[0].name
    })
  ]

  # Protect PVCs + data from accidental terraform destroy
  lifecycle {
    prevent_destroy = true
  }

  depends_on = [
    kubernetes_secret.elasticsearch_credentials,
    helm_release.elasticsearch_master,
  ]
}

# ---------------------------------------------------------------------------
# Coordinating Nodes — stateless query routing, scatter-gather
# ---------------------------------------------------------------------------
resource "helm_release" "elasticsearch_coordinating" {
  name             = "${local.cluster_name}-coordinating"
  repository       = "https://helm.elastic.co"
  chart            = "elasticsearch"
  version          = "8.5.1"
  namespace        = var.namespace
  create_namespace = false
  timeout          = 600

  values = [
    templatefile("${path.module}/templates/coordinating-values.yaml.tpl", {
      cluster_name              = local.cluster_name
      replicas                  = var.node_roles.coordinating.replicas
      master_replicas           = var.node_roles.master.replicas
      resources_requests_cpu    = var.node_roles.coordinating.resources.requests.cpu
      resources_requests_memory = var.node_roles.coordinating.resources.requests.memory
      resources_limits_cpu      = var.node_roles.coordinating.resources.limits.cpu
      resources_limits_memory   = var.node_roles.coordinating.resources.limits.memory
      heap_size                 = local.calc_heap["coordinating"]
      node_selector             = var.node_selector
      tolerations               = var.tolerations
      xpack_security_enabled         = local.xpack_security_enabled
      elastic_secret_name            = local.elastic_secret_name
      elastic_password               = var.elastic_password
      transport_cert_secret_name     = kubernetes_secret.elasticsearch_transport_certs["coordinating"].metadata[0].name
    })
  ]

  depends_on = [
    kubernetes_secret.elasticsearch_credentials,
    helm_release.elasticsearch_master,
  ]
}

# =============================================================================
# ILM Policies & Index Templates — applied via Kubernetes Job
# Targets coordinating nodes for stable endpoint
# =============================================================================

locals {
  es_url = "https://${local.cluster_name}-coordinating.${var.namespace}.svc.cluster.local:9200"

  # Build curl commands for custom ILM policies
  custom_ilm_commands = join("\n\n", [
    for prefix, days in var.custom_ilm_policies : <<-EOT
    # Custom ILM policy — ${prefix} ${days} days
    curl -sk -u "elastic:$PASSWORD" -X PUT \
      "$ES_URL/_ilm/policy/telemetry-${prefix}-${days}d" \
      -H 'Content-Type: application/json' -d '{
        "policy": {
          "phases": {
            "hot":    { "min_age": "0ms", "actions": { "set_priority": { "priority": 100 } } },
            "delete": { "min_age": "${days}d",  "actions": { "delete": {} } }
          }
        }
      }'
    EOT
  ])

  # Build curl commands for custom index templates
  custom_template_commands = join("\n\n", [
    for prefix, days in var.custom_ilm_policies : <<-EOT
    # Custom index template — priority 200, overrides global for ${prefix}-*
    curl -sk -u "elastic:$PASSWORD" -X PUT \
      "$ES_URL/_index_template/telemetry-${prefix}-ilm" \
      -H 'Content-Type: application/json' -d '{
        "index_patterns": ["${prefix}-*", "${prefix}*"],
        "priority": 200,
        "template": {
          "settings": { "index.lifecycle.name": "telemetry-${prefix}-${days}d" }
        }
      }'
    EOT
  ])
}

# Hash of ILM config to force Job replacement when policies change
# (K8s Jobs are immutable after creation)
locals {
  ilm_config_hash = substr(sha256(jsonencode({
    retention_days     = var.retention_days
    custom_ilm_policies = var.custom_ilm_policies
  })), 0, 8)
}

resource "kubernetes_job_v1" "elasticsearch_ilm_setup" {
  metadata {
    name      = "elasticsearch-ilm-setup-${local.ilm_config_hash}"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "elasticsearch-ilm-setup"
      "app.kubernetes.io/component"  = "ilm"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    backoff_limit = 5

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"      = "elasticsearch-ilm-setup"
          "app.kubernetes.io/component" = "ilm"
        }
      }

      spec {
        restart_policy = "OnFailure"

        container {
          name  = "ilm-setup"
          image = "curlimages/curl:8.7.1"

          env {
            name = "PASSWORD"
            value_from {
              secret_key_ref {
                name = "elasticsearch-credentials"
                key  = "ELASTIC_PASSWORD"
              }
            }
          }

          env {
            name  = "ES_URL"
            value = local.es_url
          }

          command = ["/bin/sh", "-c"]
          args = [<<-EOF
            # Wait for ES cluster to be green/yellow via coordinating nodes
            until curl -sk -u "elastic:$PASSWORD" "$ES_URL/_cluster/health" | grep -qE '"status":"(green|yellow)"'; do
              echo "Waiting for Elasticsearch cluster..."
              sleep 10
            done
            echo "Elasticsearch cluster is ready."

            # Global ILM policy — ${var.retention_days} day retention
            curl -sk -u "elastic:$PASSWORD" -X PUT \
              "$ES_URL/_ilm/policy/telemetry-global-${var.retention_days}d" \
              -H 'Content-Type: application/json' -d '{
                "policy": {
                  "phases": {
                    "hot":    { "min_age": "0ms", "actions": { "set_priority": { "priority": 100 } } },
                    "delete": { "min_age": "${var.retention_days}d",  "actions": { "delete": {} } }
                  }
                }
              }'

            ${local.custom_ilm_commands}

            # Global index template — priority 99, applies to all indices
            curl -sk -u "elastic:$PASSWORD" -X PUT \
              "$ES_URL/_index_template/telemetry-global-ilm" \
              -H 'Content-Type: application/json' -d '{
                "index_patterns": ["*"],
                "priority": 99,
                "template": {
                  "settings": { "index.lifecycle.name": "telemetry-global-${var.retention_days}d" }
                }
              }'

            ${local.custom_template_commands}

            echo "ILM setup complete."
          EOF
          ]
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = "10m"
  }

  depends_on = [
    helm_release.elasticsearch_master,
    helm_release.elasticsearch_data,
    helm_release.elasticsearch_coordinating,
  ]
}
