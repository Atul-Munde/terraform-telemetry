# kube-prometheus-stack Helm Values
# Production-ready configuration with HA settings

# Default alerting rules
defaultRules:
  create: ${default_rules_enabled}

# Prometheus configuration
prometheus:
  enabled: true
  prometheusSpec:
    replicas: ${prometheus_replicas}
    retention: ${prometheus_retention}
    nodeSelector:
      ${node_selector_key}: "${node_selector_value}"
    affinity:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app.kubernetes.io/name: prometheus
            topologyKey: kubernetes.io/hostname
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app.kubernetes.io/name: prometheus
    resources:
      requests:
        cpu: "${prometheus_resources_requests_cpu}"
        memory: "${prometheus_resources_requests_memory}"
      limits:
        cpu: "${prometheus_resources_limits_cpu}"
        memory: "${prometheus_resources_limits_memory}"
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: ${prometheus_storage_class}
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: ${prometheus_storage}
    # Increase startup probe to handle long WAL replay times
    startupProbe:
      httpGet:
        path: /-/ready
        port: 9090
        scheme: HTTP
      initialDelaySeconds: 0
      periodSeconds: 15
      timeoutSeconds: 5
      successThreshold: 1
      failureThreshold: 120  # 120 * 15 = 30 minutes max startup time
    podDisruptionBudget:
      enabled: true
      minAvailable: 1

# Alertmanager configuration
alertmanager:
  enabled: true
  alertmanagerSpec:
    replicas: ${alertmanager_replicas}
    nodeSelector:
      ${node_selector_key}: "${node_selector_value}"
    affinity:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app.kubernetes.io/name: alertmanager
            topologyKey: kubernetes.io/hostname
    resources:
      requests:
        cpu: "${alertmanager_resources_requests_cpu}"
        memory: "${alertmanager_resources_requests_memory}"
      limits:
        cpu: "${alertmanager_resources_limits_cpu}"
        memory: "${alertmanager_resources_limits_memory}"
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: ${alertmanager_storage_class}
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: ${alertmanager_storage}
    podDisruptionBudget:
      enabled: true
      minAvailable: 1

# Grafana configuration
grafana:
  enabled: true
  replicas: ${grafana_replicas}
  # Recreate: required for RWO PVC — kill old pod first so PVC is released before new pod starts.
  # RollingUpdate would leave both pods competing for the same ReadWriteOnce volume → stuck init.
  deploymentStrategy:
    type: Recreate
  nodeSelector:
    ${node_selector_key}: "${node_selector_value}"
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app.kubernetes.io/name: grafana
          topologyKey: kubernetes.io/hostname
  resources:
    requests:
      cpu: "${grafana_resources_requests_cpu}"
      memory: "${grafana_resources_requests_memory}"
    limits:
      cpu: "${grafana_resources_limits_cpu}"
      memory: "${grafana_resources_limits_memory}"
  persistence:
    enabled: true
%{ if grafana_existing_claim != "" }
    existingClaim: ${grafana_existing_claim}
%{ endif }
    storageClassName: ${grafana_storage_class}
    accessModes:
      - ReadWriteOnce
    size: ${grafana_storage}
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
      labelValue: "1"
      searchNamespace: ALL
      provider:
        name: default
        folder: "Default Dashboards"
        folderUid: "default-dashboards"
        disableDelete: false
        allowUiUpdates: true
  # Security context
  securityContext:
    runAsNonRoot: true
    runAsUser: 472
    fsGroup: 472

# Prometheus Operator configuration
prometheusOperator:
  enabled: true
  nodeSelector:
    ${node_selector_key}: "${node_selector_value}"
  resources:
    requests:
      cpu: "100m"
      memory: "128Mi"
    limits:
      cpu: "500m"
      memory: "512Mi"
  admissionWebhooks:
    patch:
      nodeSelector: {}

# Kube-state-metrics
kube-state-metrics:
  nodeSelector:
    ${node_selector_key}: "${node_selector_value}"

# Node exporter - runs on all nodes
prometheus-node-exporter:
  nodeSelector:
    kubernetes.io/os: linux
  tolerations:
    - effect: NoSchedule
      operator: Exists
  service:
    port: ${node_exporter_port}
    targetPort: ${node_exporter_port}
  containerPort: ${node_exporter_port}
