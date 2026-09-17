# --- Subscription ---
variable "subscription_id" {
  description = "The single Azure subscription everything in this project lives in"
  type        = string
}

variable "admin_email" {
  type = string
}