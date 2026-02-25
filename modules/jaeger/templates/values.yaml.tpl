# Jaeger Helm Values
# Template file for clean YAML configuration

provisionDataStore:
  cassandra: false
  elasticsearch: false

storage:
  type: ${storage_type}
%{ if storage_type == "elasticsearch" }
  elasticsearch:
    # ES 8.x uses HTTPS + x-pack security; skip host-verify for self-signed cert
    scheme: https
    host: ${elasticsearch_host}
    port: ${elasticsearch_port}
%{ if es_auth_enabled }
    user: "${elasticsearch_user}"
    existingSecret: "elasticsearch-credentials"
    existingSecretKey: "ELASTIC_PASSWORD"
%{ else }
    user: ""
    password: ""
%{ endif }
    cmdlineParams:
      es.tls.enabled: "true"
      es.tls.skip-host-verify: "true"
%{ endif }

# Jaeger Agent (DaemonSet) - disabled, using OTel Collector instead
agent:
  enabled: false

# Jaeger Collector
collector:
  enabled: true
  replicaCount: ${collector_replicas}
  
  service:
    type: ClusterIP
    grpc:
      port: 14250
    http:
      port: 14268
    otlp:
      grpc:
        name: otlp-grpc
        port: 4317
      http:
        name: otlp-http
        port: 4318

  resources:
    requests:
      cpu: "100m"
      memory: "256Mi"
    limits:
      cpu: "500m"
      memory: "512Mi"

  podDisruptionBudget:
    enabled: true
    minAvailable: 1

  autoscaling:
    enabled: false

  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: "25%"
      maxSurge: "25%"

  nodeSelector:
%{ if length(node_selector) > 0 ~}
%{ for key, value in node_selector ~}
    ${key}: "${value}"
%{ endfor ~}
%{ else ~}
    {}
%{ endif ~}

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

  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchExpressions:
                - key: app.kubernetes.io/component
                  operator: In
                  values:
                    - collector
            topologyKey: kubernetes.io/hostname

# Jaeger Query (UI)
query:
  enabled: true
  replicaCount: ${query_replicas}

  service:
    type: ClusterIP
    port: 16686

  nodeSelector:
%{ if length(node_selector) > 0 ~}
%{ for key, value in node_selector ~}
    ${key}: "${value}"
%{ endfor ~}
%{ else ~}
    {}
%{ endif ~}

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

  resources:
    requests:
      cpu: "100m"
      memory: "128Mi"
    limits:
      cpu: "500m"
      memory: "512Mi"

  podDisruptionBudget:
    enabled: true
    minAvailable: 1

  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: "25%"
      maxSurge: "25%"

  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchExpressions:
                - key: app.kubernetes.io/component
                  operator: In
                  values:
                    - query
            topologyKey: kubernetes.io/hostname

# Ingress - disabled by default
ingress:
  enabled: false

# All-in-one deployment - disabled for production
allInOne:
  enabled: false

# Common labels
commonLabels:
  environment: ${environment}
  managed-by: terraform
