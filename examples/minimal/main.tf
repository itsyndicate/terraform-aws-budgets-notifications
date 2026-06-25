# Minimal example — single account-wide monthly budget with Slack alerts
# Uses the default $2,000 budget limit.
#
# Prerequisites before terraform apply:
#   1. Register the Slack workspace with AWS Chatbot via the AWS Console OAuth flow.
#   2. Obtain the Workspace ID (T...) from the AWS Chatbot console.
#   3. Obtain the Channel ID (C...) from the channel URL in a browser.
#   4. After apply, run /invite @Amazon Q in the target Slack channel.

module "budget_alert" {
  source = "../../"

  budget_name                = "prod-monthly-budget"
  sns_topic_name             = "prod-budget-alerts"
  chatbot_configuration_name = "prod-budget-alerts-slack"
  chatbot_role_name          = "prod-chatbot-budget-role"

  slack_team_id    = var.slack_team_id
  slack_channel_id = var.slack_channel_id
}

# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------

variable "slack_team_id" {
  description = "Slack Workspace ID registered with AWS Chatbot (starts with T)"
  type        = string
}

variable "slack_channel_id" {
  description = "Slack Channel ID where budget alerts will be posted (starts with C)"
  type        = string
}

# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------

output "sns_topic_arn" {
  value = module.budget_alert.sns_topic_arn
}

output "budget_id" {
  value = module.budget_alert.budget_id
}
