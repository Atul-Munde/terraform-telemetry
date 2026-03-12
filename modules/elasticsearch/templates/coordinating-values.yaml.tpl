# Elasticsearch Coordinating Node Values
# Stateless coordinating-only nodes — route queries, scatter-gather, reduce

clusterName: ${cluster_name}
nodeGroup: "coordinating"

# No roles = coordinating-only
roles: []

replicas: ${replicas}

# Resource configuration — moderate CPU for scatter-gather, moderate memory for coordinating
resources:
  requests:
    cpu: "${resources_requests_cpu}"
    memory: "${resources_requests_memory}"
  limits:
    cpu: "${resources_limits_cpu}"
    memory: "${resources_limits_memory}"

# Heap size — 50% of memory limit
esJavaOpts: "-Xms${heap_size} -Xmx${heap_size}"

# No persistent storage — coordinating nodes are stateless
persistence:
  enabled: false

# Protocol — HTTPS when X-Pack security is enabled
%{ if xpack_security_enabled }
protocol: https
%{ else }
protocol: http
%{ endif }
httpPort: 9200
transportPort: 9300

# Service account
serviceAccount: elasticsearch

# Not master-eligible
minimumMasterNodes: 0

# Transport cert — Terraform-managed, shared CA across all node groups
secretMounts:
  - name: transport-certs
    secretName: ${transport_cert_secret_name}
    path: /usr/share/elasticsearch/config/transport-certs
    defaultMode: 0440

# Node selector
nodeSelector:
%{ if length(node_selector) > 0 ~}
%{ for key, value in node_selector ~}
  ${key}: "${value}"
%{ endfor ~}
%{ else ~}
  {}
%{ endif ~}

# Tolerations
tolerations:
%{ if length(tolerations) > 0 ~}
%{ for toleration in tolerations ~}
  - key: "${toleration.key}"
    operator: "${toleration.operator}"
    value: "${toleration.value}"
    effect: "${toleration.effect}"
%{ endfor ~}
%{ else ~}
  []
%{ endif ~}

# Soft anti-affinity — coordinating are stateless, prefer spread but allow co-location
antiAffinity: "soft"

# Topology spread — prefer even distribution across hosts
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app: ${cluster_name}-coordinating

# Elasticsearch config
esConfig:
  elasticsearch.yml: |
    network.host: 0.0.0.0
    node.roles: []

    # Discovery — point to dedicated master nodes
    discovery.seed_hosts:
%{ for i in range(master_replicas) ~}
      - ${cluster_name}-master-${i}.${cluster_name}-master-headless
%{ endfor ~}

    # X-Pack security
    xpack.security.enabled: ${xpack_security_enabled}
    xpack.security.enrollment.enabled: false
    xpack.security.http.ssl.enabled: false
    # Transport SSL — explicit paths to Terraform-managed shared-CA certs.
    xpack.security.transport.ssl.enabled: true
    xpack.security.transport.ssl.verification_mode: certificate
    xpack.security.transport.ssl.certificate_authorities: ["/usr/share/elasticsearch/config/transport-certs/ca.crt"]
    xpack.security.transport.ssl.certificate: "/usr/share/elasticsearch/config/transport-certs/tls.crt"
    xpack.security.transport.ssl.key: "/usr/share/elasticsearch/config/transport-certs/tls.key"

    # Performance settings
    indices.queries.cache.size: 10%

    # Auto-create indices
    action.auto_create_index: true

# Credentials secret
%{ if xpack_security_enabled }
secret:
  enabled: true
  password: "${elastic_password}"
%{ endif }

# Extra environment variables
extraEnvs:
%{ if xpack_security_enabled }
  - name: ELASTIC_PASSWORD
    valueFrom:
      secretKeyRef:
        name: ${elastic_secret_name}
        key: ELASTIC_PASSWORD
%{ else }
  - name: xpack.security.enabled
    value: "false"
%{ endif }

# Pod disruption budget
maxUnavailable: 1

# Sysctls for Elasticsearch
sysctlInitContainer:
  enabled: true
