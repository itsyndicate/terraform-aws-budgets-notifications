#-----------------------------------------------------------------------------------------------------------------------
# Module resources for AWS Budget alerts to Slack
#-----------------------------------------------------------------------------------------------------------------------

# SNS Topic for budget alert notifications
resource "aws_sns_topic" "this" {
  name = var.sns_topic_name
  tags = merge(var.tags, { Name = var.sns_topic_name })
}

# SNS Topic Policy allowing AWS Budgets and AWS Chatbot access
resource "aws_sns_topic_policy" "this" {
  arn = aws_sns_topic.this.arn

  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    sid       = "AWSBudgetsPublish"
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.this.arn]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
  }

  statement {
    sid    = "AllowChatbotSubscribe"
    effect = "Allow"
    actions = [
      "SNS:Subscribe",
      "SNS:Receive"
    ]
    resources = [aws_sns_topic.this.arn]

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
      resources = [aws_sns_topic.this.arn]

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

# Service-level anomaly monitor. If the account already has one (AWS adds
# Default-Services-Monitor when Cost Explorer is first enabled on a standalone or
# management account), import it here instead of creating a second one, or every
# anomaly is detected and sent twice.
resource "aws_ce_anomaly_monitor" "this" {
  count = var.enable_cost_anomaly_alerts ? 1 : 0

  name              = coalesce(var.cost_anomaly_monitor_name, "${var.sns_topic_name}-service-monitor")
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"

  tags = var.tags
}

# Cost Anomaly Detection findings into the same topic, and therefore the same
# Slack channel, as the budget alerts.
resource "aws_ce_anomaly_subscription" "this" {
  count = var.enable_cost_anomaly_alerts ? 1 : 0

  name             = coalesce(var.cost_anomaly_subscription_name, "${var.sns_topic_name}-anomalies")
  monitor_arn_list = [aws_ce_anomaly_monitor.this[0].arn]

  # SNS subscribers require IMMEDIATE. DAILY and WEEKLY are delivered by email
  # only, so they silently drop an SNS subscriber.
  frequency = "IMMEDIATE"

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.this.arn
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.cost_anomaly_threshold)]
    }
  }

  tags = var.tags

  # The subscription is rejected if the topic does not already allow
  # costalerts.amazonaws.com to publish.
  depends_on = [aws_sns_topic_policy.this]
}

# IAM Role for AWS Chatbot
resource "aws_iam_role" "chatbot" {
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
  name   = "ChatbotNotificationPermissions"
  role   = aws_iam_role.chatbot.id
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
resource "aws_chatbot_slack_channel_configuration" "this" {
  configuration_name = var.chatbot_configuration_name
  iam_role_arn       = aws_iam_role.chatbot.arn
  slack_channel_id   = var.slack_channel_id
  slack_team_id      = var.slack_team_id
  sns_topic_arns     = [aws_sns_topic.this.arn]
  logging_level      = "INFO"
  tags               = merge(var.tags, { Name = var.chatbot_configuration_name })
}

# AWS Budgets: Monthly cost budget
resource "aws_budgets_budget" "this" {
  name         = var.budget_name
  budget_type  = "COST"
  limit_amount = tostring(var.budget_amount)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  tags         = merge(var.tags, { Name = var.budget_name })

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

  # Alert 1: Actual spend is > 80%
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.this.arn]
  }

  # Alert 2: Forecasted spend is > 100%
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.this.arn]
  }
}
