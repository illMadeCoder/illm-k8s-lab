variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "illm-k8s-lab-rg"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "key_vault_name" {
  description = "Name of the Key Vault (must be globally unique)"
  type        = string
  default     = "illm-k8s-lab-kv"
}
