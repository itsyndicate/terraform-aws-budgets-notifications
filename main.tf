#-----------------------------------------------------------------------------------------------------------------------
# Module resources for AWS Budget alerts to Slack
#-----------------------------------------------------------------------------------------------------------------------

locals {
  # With create_sns_topic = false, the alerts go to var.sns_topic_arn, a topic that
  # another module call owns. That call also owns the topic policy.
  create_sns_topic = var.create_sns_topic
  sns_topic_arn    = local.create_sns_topic ? aws_sns_topic.this[0].arn : var.sns_topic_arn
}

# SNS Topic for budget alert notifications
resource "aws_sns_topic" "this" {
  count = local.create_sns_topic ? 1 : 0

  name = var.sns_topic_name
  tags = merge(var.tags, { Name = var.sns_topic_name })
}

# SNS Topic Policy allowing AWS Budgets and AWS Chatbot access
resource "aws_sns_topic_policy" "this" {
  count = local.create_sns_topic ? 1 : 0

  arn    = aws_sns_topic.this[0].arn
  policy = data.aws_iam_policy_document.sns_topic_policy[0].json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  count = local.create_sns_topic ? 1 : 0

  statement {
    sid       = "AWSBudgetsPublish"
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.this[0].arn]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AllowChatbotSubscribe"
    effect = "Allow"
    actions = [
      "SNS:Subscribe",
      "SNS:Receive"
    ]
    resources = [aws_sns_topic.this[0].arn]

    principals {
      type        = "Service"
      identifiers = ["chatbot.amazonaws.com"]
    }
  }

  # Only added when anomaly alerts are enabled, so topics that carry budget
  # alerts alone keep the smaller policy.
  dynamic "statement" {
    for_each = var.enable_cost_anomaly_alerts ? [1] : []
    content {
      sid       = "AWSAnomalyDetectionPublish"
      effect    = "Allow"
      actions   = ["SNS:Publish"]
      resources = [aws_sns_topic.this[0].arn]

      principals {
        type        = "Service"
        identifiers = ["costalerts.amazonaws.com"]
      }

      # Scopes the grant to this account, so the topic cannot be used as a
      # notification target by another account's subscription.
      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  # An account can have only one SERVICE monitor. AWS creates one on payer and
  # standalone accounts when Cost Explorer is enabled, together with a daily email
  # subscription that points at it. In that case the existing monitor is passed in
  # by ARN and only the subscription is created here.
  create_cost_anomaly_monitor = var.enable_cost_anomaly_alerts && var.cost_anomaly_monitor_arn == null

  cost_anomaly_monitor_name      = coalesce(var.cost_anomaly_monitor_name, "${var.sns_topic_name}-${lower(replace(var.cost_anomaly_monitor_dimension, "_", "-"))}-monitor")
  cost_anomaly_subscription_name = coalesce(var.cost_anomaly_subscription_name, "${var.sns_topic_name}-anomalies")
}

resource "aws_ce_anomaly_monitor" "this" {
  count = local.create_cost_anomaly_monitor ? 1 : 0

  name              = local.cost_anomaly_monitor_name
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = var.cost_anomaly_monitor_dimension

  tags = merge(var.tags, { Name = local.cost_anomaly_monitor_name })
}

# Cost Anomaly Detection findings into the same topic, and therefore the same
# Slack channel, as the budget alerts.
resource "aws_ce_anomaly_subscription" "this" {
  count = var.enable_cost_anomaly_alerts ? 1 : 0

  name             = local.cost_anomaly_subscription_name
  monitor_arn_list = [local.create_cost_anomaly_monitor ? aws_ce_anomaly_monitor.this[0].arn : var.cost_anomaly_monitor_arn]

  # SNS subscribers require IMMEDIATE. DAILY and WEEKLY are delivered by email
  # only, so they silently drop an SNS subscriber.
  frequency = "IMMEDIATE"

  subscriber {
    type    = "SNS"
    address = local.sns_topic_arn
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.cost_anomaly_threshold)]
    }
  }

  tags = merge(var.tags, { Name = local.cost_anomaly_subscription_name })

  # The subscription is rejected if the topic does not already allow
  # costalerts.amazonaws.com to publish.
  depends_on = [aws_sns_topic_policy.this]
}

# IAM Role for AWS Chatbot
resource "aws_iam_role" "chatbot" {
  count = var.create_chatbot ? 1 : 0

  name               = var.chatbot_role_name
  assume_role_policy = data.aws_iam_policy_document.chatbot_assume_role.json
  tags               = merge(var.tags, { Name = var.chatbot_role_name })
}

data "aws_iam_policy_document" "chatbot_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["chatbot.amazonaws.com"]
    }
  }
}

# Inline policy matching the "Notification permissions" template from the AWS Chatbot console:
# CloudWatch read + CloudWatch Logs read + SNS read — all three are required per the runbook.
resource "aws_iam_role_policy" "chatbot_notifications" {
  count = var.create_chatbot ? 1 : 0

  name   = "ChatbotNotificationPermissions"
  role   = aws_iam_role.chatbot[0].id
  policy = data.aws_iam_policy_document.chatbot_notifications.json
}

data "aws_iam_policy_document" "chatbot_notifications" {
  statement {
    sid    = "CloudWatchRead"
    effect = "Allow"
    actions = [
      "cloudwatch:Describe*",
      "cloudwatch:Get*",
      "cloudwatch:List*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CloudWatchLogsRead"
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:FilterLogEvents",
      "logs:GetLogEvents",
      "logs:GetLogGroupFields",
      "logs:GetQueryResults",
      "logs:StartQuery",
      "logs:StopQuery",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "SNSRead"
    effect = "Allow"
    actions = [
      "sns:ListTopics",
      "sns:ListSubscriptionsByTopic",
      "sns:ListSubscriptions",
      "sns:GetTopicAttributes",
      "sns:Unsubscribe",
      "sns:Subscribe"
    ]
    resources = ["*"]
  }
}

# AWS Chatbot Slack Channel Configuration
# AWS permits one configuration per Slack channel in an account. Set create_chatbot = false
# in every other module call that posts to the same channel.
resource "aws_chatbot_slack_channel_configuration" "this" {
  count = var.create_chatbot ? 1 : 0

  configuration_name = var.chatbot_configuration_name
  iam_role_arn       = aws_iam_role.chatbot[0].arn
  slack_channel_id   = var.slack_channel_id
  slack_team_id      = var.slack_team_id
  sns_topic_arns     = [local.sns_topic_arn]
  logging_level      = "INFO"

  guardrail_policy_arns       = var.chatbot_guardrail_policy_arns
  user_authorization_required = var.chatbot_user_authorization_required

  tags = merge(var.tags, { Name = var.chatbot_configuration_name })

  lifecycle {
    precondition {
      condition     = var.chatbot_configuration_name != null && var.chatbot_role_name != null && var.slack_team_id != null && var.slack_channel_id != null
      error_message = "create_chatbot = true needs chatbot_configuration_name, chatbot_role_name, slack_team_id and slack_channel_id."
    }
  }
}

# AWS Budgets: Monthly cost budget
resource "aws_budgets_budget" "this" {
  name         = var.budget_name
  budget_type  = "COST"
  limit_amount = tostring(var.budget_amount)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  lifecycle {
    precondition {
      condition     = var.create_sns_topic || var.sns_topic_arn != null
      error_message = "create_sns_topic = false needs sns_topic_arn."
    }
  }
  tags = merge(var.tags, { Name = var.budget_name })

  # Omitted when var.linked_account_ids is empty, so the budget covers the whole account or organization.
  dynamic "cost_filter" {
    for_each = length(var.linked_account_ids) > 0 ? [var.linked_account_ids] : []

    content {
      name   = "LinkedAccount"
      values = cost_filter.value
    }
  }

  # Omitted entirely when var.cost_types is null, so the budget keeps the AWS defaults.
  dynamic "cost_types" {
    for_each = var.cost_types == null ? [] : [var.cost_types]

    content {
      include_credit             = cost_types.value.include_credit
      include_discount           = cost_types.value.include_discount
      include_other_subscription = cost_types.value.include_other_subscription
      include_recurring          = cost_types.value.include_recurring
      include_refund             = cost_types.value.include_refund
      include_subscription       = cost_types.value.include_subscription
      include_support            = cost_types.value.include_support
      include_tax                = cost_types.value.include_tax
      include_upfront            = cost_types.value.include_upfront
      use_amortized              = cost_types.value.use_amortized
      use_blended                = cost_types.value.use_blended
    }
  }

  # Alert 1: actual spend is above budget_actual_threshold percent
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = var.budget_actual_threshold
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [local.sns_topic_arn]
  }

  # Alert 2: forecasted spend is above budget_forecast_threshold percent
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = var.budget_forecast_threshold
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [local.sns_topic_arn]
  }
}

# v2.1.0 created these resources without count.
moved {
  from = aws_sns_topic.this
  to   = aws_sns_topic.this[0]
}

moved {
  from = aws_sns_topic_policy.this
  to   = aws_sns_topic_policy.this[0]
}

moved {
  from = aws_iam_role.chatbot
  to   = aws_iam_role.chatbot[0]
}

moved {
  from = aws_iam_role_policy.chatbot_notifications
  to   = aws_iam_role_policy.chatbot_notifications[0]
}

moved {
  from = aws_chatbot_slack_channel_configuration.this
  to   = aws_chatbot_slack_channel_configuration.this[0]
}
