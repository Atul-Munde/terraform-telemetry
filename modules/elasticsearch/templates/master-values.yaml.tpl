# Elasticsearch Master Node Values
# Dedicated master-eligible nodes — cluster state, shard allocation, no data

clusterName: ${cluster_name}
nodeGroup: "master"

# Dedicated master role only
roles:
  - master

replicas: ${replicas}

# Resource configuration — masters are lightweight (no indexing/search)
resources:
  requests:
    cpu: "${resources_requests_cpu}"
    memory: "${resources_requests_memory}"
  limits:
    cpu: "${resources_limits_cpu}"
    memory: "${resources_limits_memory}"

# Heap size — 50% of memory limit (ES best practice)
esJavaOpts: "-Xms${heap_size} -Xmx${heap_size}"

# Volume — masters store cluster state only, small PVC is fine
volumeClaimTemplate:
  accessModes:
    - ReadWriteOnce
%{ if storage_class != "" }
  storageClassName: ${storage_class}
%{ endif }
  resources:
    requests:
      storage: ${storage_size}

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

# Quorum: floor(replicas/2) + 1
minimumMasterNodes: ${minimum_master_nodes}

# Transport cert — Terraform-managed, shared CA across all node groups
# Mounted alongside the chart's own cert to avoid cross-release CA mismatch
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

# Hard anti-affinity — one master per node, survive node failures
antiAffinity: "${anti_affinity}"

# Topology spread — distribute masters evenly across nodes (and AZs when multi-AZ)
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: ${cluster_name}-master

# Elasticsearch config
esConfig:
  elasticsearch.yml: |
    network.host: 0.0.0.0
    node.roles: [ master ]

    # Discovery — all master-eligible nodes
    discovery.seed_hosts:
%{ for i in range(replicas) ~}
      - ${cluster_name}-master-${i}.${cluster_name}-master-headless
%{ endfor ~}

    cluster.initial_master_nodes:
%{ for i in range(replicas) ~}
      - ${cluster_name}-master-${i}
%{ endfor ~}

    # X-Pack security
    xpack.security.enabled: ${xpack_security_enabled}
    xpack.security.enrollment.enabled: false
    xpack.security.http.ssl.enabled: false
    # Transport SSL — explicit paths to Terraform-managed shared-CA certs.
    # ES 8.x enforces transport TLS when security is enabled regardless of this flag;
    # setting it explicitly prevents the chart auto-generation from being used.
    xpack.security.transport.ssl.enabled: true
    xpack.security.transport.ssl.verification_mode: certificate
    xpack.security.transport.ssl.certificate_authorities: ["/usr/share/elasticsearch/config/transport-certs/ca.crt"]
    xpack.security.transport.ssl.certificate: "/usr/share/elasticsearch/config/transport-certs/tls.crt"
    xpack.security.transport.ssl.key: "/usr/share/elasticsearch/config/transport-certs/tls.key"

    # Performance settings
    indices.memory.index_buffer_size: 30%
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

# Pod disruption budget — never lose quorum
maxUnavailable: 1

# Sysctls for Elasticsearch
sysctlInitContainer:
  enabled: true
