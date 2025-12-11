output "azure_foundation_stack_id" {
  description = "Spacelift stack ID for Azure foundation"
  value       = spacelift_stack.azure_foundation.id
}

output "azure_aks_stack_id" {
  description = "Spacelift stack ID for Azure AKS"
  value       = spacelift_stack.azure_aks.id
}
