output "app_insights_connection_string" {
  description = "Fallback only - not used while workload identity auth is working"
  value       = azurerm_application_insights.aduke.connection_string
  sensitive   = true
}

output "app_insights_instrumentation_key" {
  value     = azurerm_application_insights.aduke.instrumentation_key
  sensitive = true
}

output "grafana_identity_client_id" {
  description = "Needed for Grafana's Helm values - azure.workload.identity/client-id annotation on its service account"
  value       = azurerm_user_assigned_identity.grafana.client_id
}

output "observability_resource_group_name" {
  value = azurerm_resource_group.observability.name
}

output "observability_location" {
  value = azurerm_resource_group.observability.location
}

output "application_insight_id" {
  value = azurerm_application_insights.aduke.id
}