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

  validation {
    condition     = var.budget_amount > 0
    error_message = "budget_amount must be a positive number greater than 0."
  }
}

variable "budget_actual_threshold" {
  type        = number
  description = "Percentage of the budget that actual spend must exceed to send an alert"
  default     = 80

  validation {
    condition     = var.budget_actual_threshold > 0
    error_message = "budget_actual_threshold must be greater than 0."
  }
}

variable "budget_forecast_threshold" {
  type        = number
  description = "Percentage of the budget that forecasted spend must exceed to send an alert"
  default     = 100

  validation {
    condition     = var.budget_forecast_threshold > 0
    error_message = "budget_forecast_threshold must be greater than 0."
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
  description = "Send Cost Anomaly Detection findings to the same Slack channel as the budget alerts. Creates a SERVICE monitor unless cost_anomaly_monitor_arn is set."
  default     = false
}

variable "cost_anomaly_monitor_arn" {
  type        = string
  description = "ARN of an existing anomaly monitor to subscribe to, e.g. the services monitor AWS creates with Cost Explorer. When set, the module creates only the subscription and leaves the monitor untouched."
  default     = null

  validation {
    condition     = var.cost_anomaly_monitor_arn == null || can(regex("^arn:aws:ce::[0-9]{12}:anomalymonitor/", var.cost_anomaly_monitor_arn))
    error_message = "cost_anomaly_monitor_arn must be an anomaly monitor ARN (arn:aws:ce::<account-id>:anomalymonitor/<id>)."
  }
}

variable "cost_anomaly_monitor_name" {
  type        = string
  description = "Name of the anomaly monitor the module creates. Defaults to the SNS topic name with a -service-monitor suffix. Ignored when cost_anomaly_monitor_arn is set."
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
