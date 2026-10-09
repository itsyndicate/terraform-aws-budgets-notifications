#-----------------------------------------------------------------------------------------------------------------------
# Variables
#-----------------------------------------------------------------------------------------------------------------------
variable "slack_team_id" {
  type        = string
  description = "Slack Workspace/Team ID registered with AWS Chatbot (starts with T, 9-11 chars, e.g. TXXXXXXXXX)"
  validation {
    condition     = can(regex("^T[A-Z0-9]{8,10}$", var.slack_team_id))
    error_message = "Slack Team ID must start with T followed by 8-10 uppercase alphanumeric characters."
  }
}

variable "slack_channel_id" {
  type        = string
  description = "Slack Channel ID where budget alerts should be posted (starts with C, 9-11 chars, e.g. CXXXXXXXXXX)"
  validation {
    condition     = can(regex("^C[A-Z0-9]{8,10}$", var.slack_channel_id))
    error_message = "Slack Channel ID must start with C followed by 8-10 uppercase alphanumeric characters."
  }
}

variable "budget_amount" {
  type        = number
  description = "Monthly budget limit in USD"
  default     = 2000

  validation {
    condition     = var.budget_amount > 0
    error_message = "budget_amount must be a positive number greater than 0."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources created by this module"
  default     = {}
}

variable "budget_name" {
  type        = string
  description = "Name of the monthly budget"
}

variable "sns_topic_name" {
  type        = string
  description = "Name of the SNS topic"
}

variable "chatbot_configuration_name" {
  type        = string
  description = "AWS Chatbot Slack configuration name"
}

variable "chatbot_role_name" {
  type        = string
  description = "IAM role name for AWS Chatbot"
}

variable "cost_types" {
  type = object({
    include_credit             = optional(bool)
    include_discount           = optional(bool)
    include_other_subscription = optional(bool)
    include_recurring          = optional(bool)
    include_refund             = optional(bool)
    include_subscription       = optional(bool)
    include_support            = optional(bool)
    include_tax                = optional(bool)
    include_upfront            = optional(bool)
    use_amortized              = optional(bool)
    use_blended                = optional(bool)
  })
  description = "Cost components the budget measures. Null keeps the AWS defaults (net invoiced spend); set include_credit = false to alert on gross spend on accounts that receive credits."
  default     = null
}

variable "enable_cost_anomaly_alerts" {
  type        = bool
  description = "Create a Cost Anomaly Detection monitor and send its findings to the same Slack channel as the budget alerts."
  default     = false
}

variable "cost_anomaly_monitor_name" {
  type        = string
  description = "Name of the anomaly monitor. Defaults to the SNS topic name with a -service-monitor suffix. To adopt an existing monitor, import it and set its current name here."
  default     = null
}

variable "cost_anomaly_threshold" {
  type        = number
  description = "Minimum absolute anomaly impact in USD before a finding is sent."
  default     = 100
}

variable "cost_anomaly_subscription_name" {
  type        = string
  description = "Name of the anomaly subscription. Defaults to the SNS topic name with a -anomalies suffix."
  default     = null
}
