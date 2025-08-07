
variable "discord_webhook_url" {
  description = "Discord Webhook URL"
  type        = string
  sensitive   = true
}

variable "alert_email" {
  description = "Email for SNS alerts"
  type        = string
}
