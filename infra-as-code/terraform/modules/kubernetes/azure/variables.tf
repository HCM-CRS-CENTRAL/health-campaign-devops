variable "name" {}
variable "node_count" {}
variable "vm_size" {}
variable "resource_group" {}
variable "location" {}
variable "environment" {}
variable "vnet_subnet_id" {}
variable "os_disk_size_gb" {}
variable "enable_auto_scaling" {
  description = "Enable auto scaling for the default node pool"
  type        = bool
  default     = false
}
variable "min_node_count" {
  description = "Minimum number of nodes for auto scaling"
  type        = number
  default     = 1
}
variable "max_node_count" {
  description = "Maximum number of nodes for auto scaling"
  type        = number
  default     = 10
}
variable "oidc_issuer_enabled" {
  description = "Enable the OIDC issuer (required for workload identity)"
  type        = bool
  default     = false
}

variable "workload_identity_enabled" {
  description = "Enable Microsoft Entra Workload Identity (requires oidc_issuer_enabled)"
  type        = bool
  default     = false
}

variable "service_principal_client_id" {
  description = "Client ID of a service principal to run the cluster as. null (default) = system-assigned managed identity."
  type        = string
  default     = null
}

variable "service_principal_client_secret" {
  description = "Client secret for service_principal_client_id."
  type        = string
  default     = null
  sensitive   = true
}
