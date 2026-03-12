# Namespace Module

Creates and manages the Kubernetes namespace for the telemetry stack.  
All other modules depend on this module and use the namespace name it outputs.

## Usage

```hcl
module "namespace" {
  source = "./modules/namespace"

  namespace        = "telemetry"
  create_namespace = true

  labels = {
    environment = "staging"
    team        = "platform"
    cost-center = "engineering"
  }
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `namespace` | Namespace name | string | `"telemetry"` |
| `create_namespace` | Whether to create the namespace (set `false` if it already exists) | bool | `true` |
| `labels` | Labels to apply to the namespace | map(string) | `{}` |
| `annotations` | Annotations to apply to the namespace | map(string) | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `name` | The namespace name (same as input — used by all dependent modules) |

## Notes

- Set `create_namespace = false` if the namespace was created outside Terraform (e.g. by another team or tool).
- Labels propagate to all resources in the namespace for filtering and cost attribution.
- This module must be applied before any other module in the stack (all others have `depends_on = [module.namespace]`).
