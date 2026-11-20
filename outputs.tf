#-----------------------------------------------------------------------------------------------------------------------
# Outputs
#-----------------------------------------------------------------------------------------------------------------------
output "sns_topic_arn" {
  value       = local.sns_topic_arn
  description = "ARN of the SNS topic used for budget alerts, created by the module or passed in"
}

output "chatbot_configuration_arn" {
  value       = one(aws_chatbot_slack_channel_configuration.this[*].chat_configuration_arn)
  description = "ARN of the AWS Chatbot Slack configuration. Null when create_chatbot is false"
}

output "budget_id" {
  value       = aws_budgets_budget.this.id
  description = "The ID of the AWS Budget"
}

output "chatbot_iam_role_arn" {
  value       = one(aws_iam_role.chatbot[*].arn)
  description = "ARN of the IAM role used by AWS Chatbot. Null when create_chatbot is false"
}

output "cost_anomaly_monitor_arn" {
  value       = var.enable_cost_anomaly_alerts ? coalesce(var.cost_anomaly_monitor_arn, one(aws_ce_anomaly_monitor.this[*].arn)) : null
  description = "ARN of the Cost Anomaly Detection monitor the subscription uses, created by the module or passed in. Null when anomaly alerts are disabled"
}

output "cost_anomaly_subscription_arn" {
  value       = one(aws_ce_anomaly_subscription.this[*].arn)
  description = "ARN of the Cost Anomaly Detection subscription. Null when anomaly alerts are disabled"
}
