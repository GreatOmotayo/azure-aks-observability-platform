resource "azurerm_monitor_action_group" "ops_notifications" {
  name                = "ag-aduke-ops"
  resource_group_name = data.terraform_remote_state.core.outputs.observability_resource_group_name
  short_name          = "adukeops"

  email_receiver {
    name          = "primary-email"
    email_address = var.admin_email # your email
  }

  # webhook_receiver {
  #   name = "teams-webhook"
  #   service_uri = data.azurerm_key_vault_secret.teams_webhook.value
  # }
}

# --- a second, lower urgency group

resource "azurerm_monitor_action_group" "lower_ops_notifications" {
  name                = "ag-aduke-ops-ticket"
  resource_group_name = data.terraform_remote_state.core.outputs.observability_resource_group_name
  short_name          = "adukeslow"

  email_receiver {
    name          = "primary-email"
    email_address = var.admin_email # your email
  }
}

# data "azurerm_key_vault_secret" "teams_webhook" {
#   name = "alertmanager-teams-webhook" # same secret 
#   key_vault_id = data.terraform_remote_state.aduke.outputs.vault_id
# }
