# Complete example — separate budget alerts for production and staging environments,
# both routing to the same Slack workspace but different channels.
# Demonstrates full tagging, custom budget amounts, Cost Anomaly Detection
# on an existing monitor, and multi-environment usage.
#
# Prerequisites before terraform apply:
#   1. Register the Slack workspace with AWS Chatbot via the AWS Console OAuth flow.
#   2. Obtain the Workspace ID (T...) from the AWS Chatbot console.
#   3. Obtain the Channel IDs (C...) from the channel URLs in a browser.
#      Channels must be owned by the registered workspace (sharing them is fine).
#   4. After apply, run /invite @Amazon Q in each target Slack channel.

# --- Production budget ---
module "budget_alert_prod" {
  source = "../../"

  budget_name   = "prod-monthly-budget"
  budget_amount = 5000

  # The account already has the services monitor AWS created with Cost Explorer,
  # so only the subscription is added to it.
  enable_cost_anomaly_alerts = true
  cost_anomaly_monitor_arn   = var.cost_anomaly_monitor_arn
  cost_anomaly_threshold     = 50

  sns_topic_name             = "prod-budget-alerts"
  chatbot_configuration_name = "prod-budget-alerts-slack"
  chatbot_role_name          = "prod-chatbot-budget-role"

  slack_team_id    = var.slack_team_id
  slack_channel_id = var.slack_channel_id_prod # e.g. #aws-budget-alerts-prod

  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
    Team        = "devops"
    Purpose     = "cost-alerting"
  }
}

# --- Staging budget ---
module "budget_alert_staging" {
  source = "../../"

  budget_name   = "staging-monthly-budget"
  budget_amount = 1000

  sns_topic_name             = "staging-budget-alerts"
  chatbot_configuration_name = "staging-budget-alerts-slack"
  chatbot_role_name          = "staging-chatbot-budget-role"

  slack_team_id    = var.slack_team_id
  slack_channel_id = var.slack_channel_id_staging # e.g. #aws-budget-alerts-staging

  tags = {
    Environment = "staging"
    ManagedBy   = "terraform"
    Team        = "devops"
    Purpose     = "cost-alerting"
  }
}

# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------

variable "slack_team_id" {
  description = "Slack Workspace ID registered with AWS Chatbot (starts with T). Shared by both environments."
  type        = string
}

variable "slack_channel_id_prod" {
  description = "Slack Channel ID for production budget alerts (starts with C)"
  type        = string
}

variable "slack_channel_id_staging" {
  description = "Slack Channel ID for staging budget alerts (starts with C)"
  type        = string
}

variable "cost_anomaly_monitor_arn" {
  description = "ARN of the existing services anomaly monitor in the production account (aws ce get-anomaly-monitors)"
  type        = string
}

# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------

output "prod_sns_topic_arn" {
  description = "SNS topic ARN for production budget alerts"
  value       = module.budget_alert_prod.sns_topic_arn
}

output "prod_chatbot_iam_role_arn" {
  description = "IAM role ARN used by the production Chatbot configuration"
  value       = module.budget_alert_prod.chatbot_iam_role_arn
}

output "prod_budget_id" {
  description = "Production budget ID"
  value       = module.budget_alert_prod.budget_id
}

output "staging_sns_topic_arn" {
  description = "SNS topic ARN for staging budget alerts"
  value       = module.budget_alert_staging.sns_topic_arn
}

output "staging_budget_id" {
  description = "Staging budget ID"
  value       = module.budget_alert_staging.budget_id
}
