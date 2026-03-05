replicaCount: ${operator_replicas}

# Restrict operator to only watch the telemetry namespace.
# Set to "" for cluster-wide watching (required if deploying VMCluster in multiple namespaces).
watchNamespace: "${watch_namespace}"

logLevel: "INFO"

# Use envflag so all VM operator flags can be set via environment variables.
env:
  - name: VM_ENABLEDPROMETHEUSCONVERTEROWNERREFERENCES
    value: "true"

resources:
  requests:
    cpu: "${operator_resources_requests_cpu}"
    memory: "${operator_resources_requests_memory}"
  limits:
    cpu: "${operator_resources_limits_cpu}"
    memory: "${operator_resources_limits_memory}"

%{ if length(node_selector) > 0 ~}
nodeSelector:
%{ for k, v in node_selector ~}
  ${k}: "${v}"
%{ endfor ~}
%{ endif ~}

# Pod disruption budget — operator uses leader election, always keep >= 1 available
podDisruptionBudget:
  enabled: true
  minAvailable: 1
