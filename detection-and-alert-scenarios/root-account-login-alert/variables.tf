# variables.tf

variable "discord_webhook_url" {
  description = "Discord Webhook URL"
  type        = string
}

variable "notification_email" {
  description = "Email address for alerts"
  type        = string
}