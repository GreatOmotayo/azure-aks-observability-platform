# --- Subscription ---
variable "subscription_id" {
  description = "The single Azure subscription everything in this project lives in"
  type        = string
}

variable "location" {
  description = "Azure region for observability resources"
  type = string
  default = "centralus"
}

variable "resource_group_name" {
  description = "Name of the resource group for observability resources"
  type = string
  default = "rg-aks-observability"
}

variable "grafana_namespace" {
  description = "Kubernetes namespace for Grafana will run in"
  type = string
  default = "monitoring"
}

variable "grafana_service_account_name" {
  description = "The name of the service account for Grafana's pod"
  type = string
  default = "grafana"
}

variable "grafana_admin_password" {
  description = "Grafana Password"
  type = string
}

