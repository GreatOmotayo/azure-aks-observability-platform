data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "observability" {
  name     = var.resource_group_name
  location = var.location
}

# Workspace-based Application Insights
resource "azurerm_application_insights" "aduke" {
  name                = "appi-aduke"
  location            = azurerm_resource_group.observability.location
  resource_group_name = azurerm_resource_group.observability.name
  workspace_id        = data.terraform_remote_state.logging.outputs.workspace_id
  application_type    = "Node.JS"
}

# ---- Aduke's role assignment ----
resource "azurerm_role_assignment" "aduke_metrics_publisher" {
  scope                = azurerm_application_insights.aduke.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = data.terraform_remote_state.aduke.outputs.aduke_workload_identity_principal_id
}

# ---- Grafana's dedicated identity ---
resource "azurerm_user_assigned_identity" "grafana" {
  name                = "mi-grafana-monitor-reader"
  resource_group_name = azurerm_resource_group.observability.name
  location            = azurerm_resource_group.observability.location
}

# ---- Federates this identity to Grafana's specific Kubernetes service account ----
resource "azurerm_federated_identity_credential" "grafana" {
  name                      = "grafana-workload-identity"
  user_assigned_identity_id = azurerm_user_assigned_identity.grafana.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = data.terraform_remote_state.aduke.outputs.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.grafana_namespace}:${var.grafana_service_account_name}"
}

# Grafana's identity needs to read its own admin-password secret via the CSI driver
resource "azurerm_role_assignment" "grafana_keyvault_secrets_reader" {
  scope                = data.terraform_remote_state.aduke.outputs.vault_id
  role_definition_name = "Key Vault Secrets User"   # read-only, least privilege
  principal_id         = azurerm_user_assigned_identity.grafana.principal_id
}


# ---- Log Analytics Reader
resource "azurerm_role_assignment" "grafana_log_reader" {
  scope                = data.terraform_remote_state.logging.outputs.workspace_id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azurerm_user_assigned_identity.grafana.principal_id
}

resource "azurerm_key_vault_secret" "aduke_app_insights_connection_string" {
  name         = "aduke-app-insights-connection-string"
  value        = azurerm_application_insights.aduke.connection_string
  key_vault_id = data.terraform_remote_state.aduke.outputs.vault_id
}

resource "azurerm_key_vault_secret" "grafana_password" {
  name         = "grafana-admin-password"
  value        = var.grafana_admin_password
  key_vault_id = data.terraform_remote_state.aduke.outputs.vault_id
}