variable "namespace" {
  description = "Namespace name"
  type        = string
}

variable "create_namespace" {
  description = "Whether to create the namespace or use existing"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to namespace"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Annotations to apply to namespace"
  type        = map(string)
  default     = {}
}
