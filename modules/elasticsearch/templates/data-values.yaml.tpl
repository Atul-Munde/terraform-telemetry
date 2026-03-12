# Elasticsearch Data Node Values
# Dedicated data + ingest nodes — indexing, search, aggregations

clusterName: ${cluster_name}
nodeGroup: "data"

# Data + ingest roles (combined to reduce pod count)
roles:
  - data
  - data_content
  - data_hot
  - ingest

replicas: ${replicas}

# Resource configuration — data nodes are the heaviest
resources:
  requests:
    cpu: "${resources_requests_cpu}"
    memory: "${resources_requests_memory}"
  limits:
    cpu: "${resources_limits_cpu}"
    memory: "${resources_limits_memory}"

# Heap size — 50% of memory limit (ES best practice, max 31g)
esJavaOpts: "-Xms${heap_size} -Xmx${heap_size}"

# Volume — bulk of storage lives here
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

# Not master-eligible — set to 0
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

# Hard anti-affinity — one data node per K8s node
antiAffinity: "${anti_affinity}"

# Topology spread — distribute data nodes evenly across hosts (and AZs when multi-AZ)
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: ${cluster_name}-data

# Elasticsearch config
esConfig:
  elasticsearch.yml: |
    network.host: 0.0.0.0
    node.roles: [ data, data_content, data_hot, ingest ]

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

# Pod disruption budget — allow rolling restarts but maintain majority
maxUnavailable: 1

# Sysctls for Elasticsearch
sysctlInitContainer:
  enabled: true
