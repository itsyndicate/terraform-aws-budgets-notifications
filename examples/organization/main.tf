# Organization example — runs in the management account.
# One organization budget, one budget per member account, and SERVICE plus
# LINKED_ACCOUNT anomaly alerts. All calls post to one Slack channel: the org call
# owns the SNS topic and the Chatbot configuration, the other calls publish to its topic.
#
# Prerequisites before terraform apply:
#   1. Register the Slack workspace with AWS Chatbot via the AWS Console OAuth flow.
#   2. Obtain the Workspace ID (T...) from the AWS Chatbot console.
#   3. Obtain the Channel ID (C...) from the channel URL in a browser.
#   4. Find the services monitor AWS created with Cost Explorer: aws ce get-anomaly-monitors
#   5. After apply, run /invite @Amazon Q in the target Slack channel.

locals {
  # Credits and refunds stay out of the budgets, so the alerts follow gross usage.
  cost_types = {
    include_credit = false
    include_refund = false
  }
}

# --- Organization budget and services anomaly alerts ---
module "budget_alert_org" {
  source = "../../"

  budget_name   = "org-monthly-budget"
  budget_amount = 1000
  cost_types    = local.cost_types

  enable_cost_anomaly_alerts = true
  cost_anomaly_monitor_arn   = var.services_monitor_arn
  cost_anomaly_threshold     = 10

  sns_topic_name             = "org-budget-alerts"
  chatbot_configuration_name = "org-budget-alerts-slack"
  chatbot_role_name          = "org-chatbot-budget-role"

  slack_team_id    = var.slack_team_id
  slack_channel_id = var.slack_channel_id
}

# --- Member account budget and linked account anomaly alerts ---
module "budget_alert_workloads" {
  source = "../../"

  budget_name        = "workloads-monthly-budget"
  budget_amount      = 600
  linked_account_ids = [var.workloads_account_id]
  cost_types         = local.cost_types

  enable_cost_anomaly_alerts     = true
  cost_anomaly_monitor_dimension = "LINKED_ACCOUNT"
  cost_anomaly_threshold         = 10

  sns_topic_name   = "workloads-budget-alerts"
  create_sns_topic = false
  sns_topic_arn    = module.budget_alert_org.sns_topic_arn
  create_chatbot   = false
}

# --- Member account budget ---
module "budget_alert_sandbox" {
  source = "../../"

  budget_name        = "sandbox-monthly-budget"
  budget_amount      = 250
  linked_account_ids = [var.sandbox_account_id]
  cost_types         = local.cost_types

  sns_topic_name   = "sandbox-budget-alerts"
  create_sns_topic = false
  sns_topic_arn    = module.budget_alert_org.sns_topic_arn
  create_chatbot   = false
}

# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------

variable "slack_team_id" {
  description = "Slack Workspace ID registered with AWS Chatbot (starts with T)"
  type        = string
}

variable "slack_channel_id" {
  description = "Slack Channel ID for all cost alerts (starts with C)"
  type        = string
}

variable "services_monitor_arn" {
  description = "ARN of the services anomaly monitor AWS created with Cost Explorer (aws ce get-anomaly-monitors)"
  type        = string
}

variable "workloads_account_id" {
  description = "ID of the member account the workloads budget measures"
  type        = string
}

variable "sandbox_account_id" {
  description = "ID of the member account the sandbox budget measures"
  type        = string
}

# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------

output "budget_ids" {
  description = "IDs of the three budgets"
  value = {
    org       = module.budget_alert_org.budget_id
    workloads = module.budget_alert_workloads.budget_id
    sandbox   = module.budget_alert_sandbox.budget_id
  }
}

output "linked_account_monitor_arn" {
  description = "ARN of the LINKED_ACCOUNT anomaly monitor the module created"
  value       = module.budget_alert_workloads.cost_anomaly_monitor_arn
}
