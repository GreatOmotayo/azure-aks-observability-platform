data "terraform_remote_state" "logging" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "omotayotfstate"
    container_name       = "tf-state"
    key                  = "platform-logging.tfstate"
    use_azuread_auth     = true
  }
}

data "terraform_remote_state" "aduke" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "omotayotfstate"
    container_name       = "tf-state"
    key                  = "aks-container-platform.tfstate"
    use_azuread_auth     = true
  }
}