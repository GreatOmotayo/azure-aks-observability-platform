# terraform/alerts/remote_state.tf
data "terraform_remote_state" "core" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "omotayotfstate"
    container_name       = "tf-state"
    key                  = "aks-observability-core.tfstate"
    use_azuread_auth     = true
  }
}