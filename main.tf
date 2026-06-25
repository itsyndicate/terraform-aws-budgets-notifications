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
