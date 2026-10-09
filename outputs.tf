#-----------------------------------------------------------------------------------------------------------------------
# Outputs
#-----------------------------------------------------------------------------------------------------------------------
output "sns_topic_arn" {
  value       = aws_sns_topic.this.arn
  description = "ARN of the SNS topic used for budget alerts"
}

output "chatbot_configuration_arn" {
  value       = aws_chatbot_slack_channel_configuration.this.chat_configuration_arn
  description = "ARN of the AWS Chatbot Slack configuration"
}

output "budget_id" {
  value       = aws_budgets_budget.this.id
  description = "The ID of the AWS Budget"
}

output "chatbot_iam_role_arn" {
  value       = aws_iam_role.chatbot.arn
  description = "ARN of the IAM role used by AWS Chatbot"
}

output "cost_anomaly_monitor_arn" {
  value       = one(aws_ce_anomaly_monitor.this[*].arn)
  description = "ARN of the Cost Anomaly Detection monitor. Null when anomaly alerts are disabled"
}
