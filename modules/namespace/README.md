# Namespace Module

Creates and manages Kubernetes namespace for observability stack.

## Usage

```hcl
module "namespace" {
  source = "./modules/namespace"

  namespace        = "observability"
  create_namespace = true
  
  labels = {
    environment = "production"
    team        = "platform"
  }
  
  annotations = {
    "description" = "Observability stack namespace"
  }
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| namespace | Namespace name | string | "observability" |
| create_namespace | Whether to create the namespace | bool | true |
| labels | Labels to apply | map(string) | {} |
| annotations | Annotations to apply | map(string) | {} |

## Outputs

| Name | Description |
|------|-------------|
| name | Created namespace name |

## Notes

- Set `create_namespace = false` if namespace already exists
- Labels are applied for resource organization
- Annotations can include metadata like owner, description
