# Elasticsearch Helm Values
# Template file for clean YAML configuration

replicas: ${replicas}

# Resource configuration
resources:
  requests:
    cpu: "${resources_requests_cpu}"
    memory: "${resources_requests_memory}"
  limits:
    cpu: "${resources_limits_cpu}"
    memory: "${resources_limits_memory}"

# Heap size - must be equal for both Xms and Xmx
esJavaOpts: "-Xms${heap_size} -Xmx${heap_size}"

# Volume configuration
volumeClaimTemplate:
  accessModes:
    - ReadWriteOnce
%{ if storage_class != "" }
  storageClassName: ${storage_class}
%{ endif }
  resources:
    requests:
      storage: ${storage_size}

# Protocol — must be https when X-Pack security is enabled (ES 8.x auto-enables HTTP TLS)
# TLS is pod-to-pod only; external TLS is terminated at the ALB
%{ if xpack_security_enabled }
protocol: https
%{ else }
protocol: http
%{ endif }
httpPort: 9200
transportPort: 9300

# Create service account
serviceAccount: elasticsearch

# Minimal master nodes
minimumMasterNodes: 1

# Secret mounts - empty to prevent SSL cert creation
secretMounts: []

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

# Anti-affinity to spread pods across nodes
antiAffinity: "soft"

# Elasticsearch config
esConfig:
  elasticsearch.yml: |
    network.host: 0.0.0.0

    # X-Pack security — enabled when elastic_password is provided, disabled otherwise
    xpack.security.enabled: ${xpack_security_enabled}
    xpack.security.enrollment.enabled: false
    # Keep HTTP SSL off — TLS is terminated at the ALB/load balancer
    xpack.security.http.ssl.enabled: false
    xpack.security.transport.ssl.enabled: false

    # Performance settings
    indices.memory.index_buffer_size: 30%
    indices.queries.cache.size: 10%

    # Auto-create indices
    action.auto_create_index: true

# Let the chart create elasticsearch-master-credentials with OUR password so that
# both Kibana pre-install job (which reads from that secret) and our own secret agree.
%{ if xpack_security_enabled }
secret:
  enabled: true
  password: "${elastic_password}"
%{ endif }

# Extra environment variables — password from secret when X-Pack is enabled
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
