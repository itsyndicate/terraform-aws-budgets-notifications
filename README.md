# aws-budgets-alert

Terraform module that provisions a monthly AWS cost budget with Slack notifications delivered via Amazon SNS and AWS Chatbot (Amazon Q Developer in chat applications).

## Architecture

```
┌─────────────────────┐     SNS:Publish      ┌──────────────────────┐
│    AWS Budgets      │ ──────────────────►  │     SNS Topic        │
│  (80% actual +      │                      │  (Standard, policy   │
│  100% forecasted)   │                      │   allows Budgets +   │
└─────────────────────┘                      │   Chatbot principals)│
                                             └──────────┬───────────┘
                                                        │ SNS:Subscribe (https)
                                                        ▼
                                             ┌──────────────────────┐
                                             │    AWS Chatbot       │
                                             │  (Slack channel      │
                                             │   configuration +    │
                                             │   IAM role)          │
                                             └──────────┬───────────┘
                                                        │ Slack API
                                                        ▼
                                             ┌──────────────────────┐
                                             │   Slack Channel      │
                                             │  #your-alerts-chan   │
                                             └──────────────────────┘
```

## Alert thresholds

The module creates exactly two alert thresholds per the ITsyndicate fresh-account baseline (`0004-budget-alert-thresholds`):

| # | Threshold | Type | Purpose |
|---|-----------|------|---------|
| 1 | 80% of budget | `ACTUAL` | Money already spent has crossed 80% of the monthly cap — reactive signal. |
| 2 | 100% of budget | `FORECASTED` | AWS Budgets projects month-end spend will exceed the cap — preventive signal while there is still time to act. |

---

## ⚠️ Prerequisites — MUST be completed before `terraform apply`

The `aws_chatbot_slack_channel_configuration` resource requires the Slack workspace to be **already registered** with AWS Chatbot via OAuth. Terraform cannot perform this OAuth handshake — it is a one-time manual step.

### Step 1 — Register the Slack workspace with AWS Chatbot

1. Open the **AWS Console → AWS Chatbot** (or search "Amazon Q Developer in chat applications").
2. Under **Configure a chat client**, choose **Slack** → click **Configure**.
3. You will be redirected to Slack to authorise the AWS Chatbot OAuth app. Confirm you are in the correct workspace, then click **Allow**.
4. On the resulting page, note the **Workspace ID** — it starts with `T` (e.g. `TXXXXXXXXX`). This is your `slack_team_id` input.

> This authorisation is **one-time per workspace**. If the workspace is already registered, skip to Step 2.

### Step 2 — Get the Slack channel ID

1. In Slack, create a dedicated alerts channel (e.g. `#aws-budget-alerts`) if it does not already exist.
   > **Important:** AWS Chatbot does **not** support Slack Connect (shared) channels. The channel must be a regular (non-shared) channel inside the workspace registered in Step 1.
2. Open the channel in a browser. The URL looks like:
   ```
   https://app.slack.com/client/TXXXXXXXXX/CXXXXXXXXXX
                                   └─ team id ─┘ └─ channel id ─┘
   ```
3. The trailing segment (`CXXXXXXXXXX`) is your `slack_channel_id` input.

Once both IDs are in hand, proceed with `terraform apply`.

---

## Examples

| Example | Description |
|---------|-------------|
| [minimal](./examples/minimal) | Single account-wide budget with default $2,000 limit. Only required variables. |
| [complete](./examples/complete) | Separate budgets for production and staging, each routing to a different Slack channel, with full tagging and custom budget amounts. |

---

## Usage

### Plain Terraform

```hcl
module "aws_budgets_alert" {
  source = "../../_catalog/modules/aws-budgets-alert"

  # Budget
  budget_name   = "prod-monthly-budget"
  budget_amount = 3000

  # SNS
  sns_topic_name = "prod-budget-alerts"

  # AWS Chatbot
  chatbot_configuration_name = "prod-budget-alerts-slack"
  chatbot_role_name          = "prod-chatbot-budget-role"

  # Slack — obtain these from the Prerequisites section above
  slack_team_id    = "<YOUR_SLACK_TEAM_ID>"
  slack_channel_id = "<YOUR_SLACK_CHANNEL_ID>"

  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
    Team        = "devops"
  }
}
```

### Terragrunt (envcommon pattern)

`_catalog/envcommon/aws-budgets-alert.hcl` — shared naming, sourced by every environment:

```hcl
terraform {
  source = "${dirname(find_in_parent_folders("root.terragrunt.hcl"))}/_catalog/modules//aws-budgets-alert"
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  prefix           = local.environment_vars.locals.prefix
}

inputs = {
  budget_name                = "${local.prefix}-monthly-budget"
  sns_topic_name             = "${local.prefix}-budget-alerts"
  chatbot_configuration_name = "${local.prefix}-budget-alerts-slack"
  chatbot_role_name          = "${local.prefix}-chatbot-budget-role"
}
```

`environments/_shared/us-east-1/budgets/terragrunt.hcl` — environment-specific overrides:

```hcl
include "root" {
  path = find_in_parent_folders("root.terragrunt.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.terragrunt.hcl"))}/_catalog/envcommon/aws-budgets-alert.hcl"
  expose = true
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  prefix           = local.environment_vars.locals.prefix
}

inputs = {
  slack_team_id    = "<YOUR_SLACK_TEAM_ID>"    # Slack workspace ID from AWS Chatbot OAuth registration
  slack_channel_id = "<YOUR_SLACK_CHANNEL_ID>" # #aws-budget-alerts
  budget_amount    = 2700
}
```

---

## Post-apply — invite the bot to the channel

After `terraform apply` succeeds, Chatbot will subscribe to the SNS topic automatically. However, it **cannot post messages** into a channel it has not been invited to. In Slack, in your alerts channel, run:

```
/invite @Amazon Q
```

> The Slack app is named **@Amazon Q** even though the AWS-side service is called AWS Chatbot. Both names refer to the same component.

To verify the SNS subscription was confirmed:

```bash
aws sns list-subscriptions-by-topic \
  --topic-arn "<sns_topic_arn output>" \
  --region us-east-1
```

The `SubscriptionArn` field must be a full ARN (not the string `PendingConfirmation`). If it shows `PendingConfirmation`, re-check the SNS topic policy and re-create the Chatbot channel configuration resource.

---

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws provider | ~> 6.0 |

---

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `slack_team_id` | Slack Workspace/Team ID registered with AWS Chatbot. Starts with `T`, 9–11 chars. Obtain from the AWS Chatbot console after OAuth registration. | `string` | — | yes |
| `slack_channel_id` | Slack Channel ID where budget alerts will be posted. Starts with `C`, 9–11 chars. Obtain from the channel URL in a browser. Must be a regular channel — Slack Connect (shared) channels are not supported. | `string` | — | yes |
| `budget_name` | Name of the monthly cost budget. Should make scope obvious (e.g. `prod-monthly-budget`). | `string` | — | yes |
| `sns_topic_name` | Name of the SNS Standard topic that bridges Budgets to Chatbot. | `string` | — | yes |
| `chatbot_configuration_name` | Name of the AWS Chatbot Slack channel configuration. Must be unique within the AWS account. | `string` | — | yes |
| `chatbot_role_name` | Name of the IAM role assumed by AWS Chatbot. | `string` | — | yes |
| `budget_amount` | Monthly budget limit in USD. Must be greater than 0. | `number` | `2000` | no |
| `tags` | Tags to apply to all taggable resources created by this module. | `map(string)` | `{}` | no |

---

## Outputs

| Name | Description |
|------|-------------|
| `sns_topic_arn` | ARN of the SNS topic used for budget alerts. Use this to wire additional subscribers (e.g. email, Lambda). |
| `chatbot_configuration_arn` | ARN of the AWS Chatbot Slack channel configuration. |
| `chatbot_iam_role_arn` | ARN of the IAM role used by AWS Chatbot. Use this to attach additional policies if needed. |
| `budget_id` | ID of the AWS Budget (format: `AccountId:BudgetName`). |

---

## Resources created

| Resource | Type | Purpose |
|----------|------|---------|
| `aws_sns_topic.this` | `aws_sns_topic` | Receives alert payloads from Budgets, delivers them to Chatbot. |
| `aws_sns_topic_policy.this` | `aws_sns_topic_policy` | Grants `budgets.amazonaws.com` publish access and `chatbot.amazonaws.com` subscribe/receive access. |
| `aws_iam_role.chatbot` | `aws_iam_role` | IAM role assumed by the Chatbot service. |
| `aws_iam_role_policy.chatbot_notifications` | `aws_iam_role_policy` | Inline policy granting CloudWatch read, CloudWatch Logs read, and SNS read — equivalent to the "Notification permissions" template in the AWS Chatbot console. |
| `aws_chatbot_slack_channel_configuration.this` | `aws_chatbot_slack_channel_configuration` | Wires the SNS topic to the Slack channel. Logging level set to `INFO`. |
| `aws_budgets_budget.this` | `aws_budgets_budget` | Monthly COST budget with 80% actual and 100% forecasted alert thresholds. |

---

## IAM permissions

The Chatbot IAM role is granted the following permissions (inline policy `ChatbotNotificationPermissions`):

| Scope | Actions |
|-------|---------|
| CloudWatch | `Describe*`, `Get*`, `List*` |
| CloudWatch Logs | `DescribeLogGroups`, `DescribeLogStreams`, `FilterLogEvents`, `GetLogEvents`, `GetLogGroupFields`, `GetQueryResults`, `StartQuery`, `StopQuery` |
| SNS | `GetTopicAttributes`, `ListSubscriptions`, `ListSubscriptionsByTopic`, `ListTopics`, `Subscribe`, `Unsubscribe` |

These mirror the **Notification permissions** template offered by the AWS Chatbot setup wizard and are the minimum required for formatted alert delivery and diagnostic log shipping.

---

## Verification

The only reliable end-to-end test is a real notification from the AWS Budgets service. Plain `aws sns publish` CLI messages are rejected by Chatbot with "Event received is not supported" — this is expected behaviour, not a configuration error.

To trigger a real alert on demand, temporarily lower the budget limit below your current month-to-date spend:

```bash
# 1. Check current month spend
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --query 'ResultsByTime[0].Total.BlendedCost.Amount' \
  --output text

# 2. Lower the limit to $1 to guarantee an immediate breach
aws budgets update-budget \
  --account-id <account-id> \
  --new-budget '{"BudgetName":"<budget-name>","BudgetType":"COST","BudgetLimit":{"Amount":"1","Unit":"USD"},"TimeUnit":"MONTHLY"}'

# 3. Wait ~15 minutes for Budgets to evaluate, then restore
aws budgets update-budget \
  --account-id <account-id> \
  --new-budget '{"BudgetName":"<budget-name>","BudgetType":"COST","BudgetLimit":{"Amount":"2000","Unit":"USD"},"TimeUnit":"MONTHLY"}'
```

Check Chatbot logs if the Slack card does not arrive:

```bash
aws logs tail /aws/chatbot/<chatbot_configuration_name> \
  --since 30m \
  --region us-east-1
```

---

## Known limitations

- **Slack Connect (shared) channels are not supported.** AWS Chatbot can only post to regular channels inside the workspace registered via OAuth. Attempting to use a shared channel results in silent delivery failure.
- **The Slack workspace OAuth registration is a one-time manual step** that cannot be automated by Terraform. It must be completed in the AWS Console before the first `terraform apply`.
- **`aws sns publish` cannot be used to test the Chatbot integration.** Chatbot only renders events published by supported AWS services (Budgets, CloudWatch Alarms, etc.) in their native structured format. Plain-text SNS messages will always be rejected.
- **Forecasted alerts may fire in the first few days of a new billing cycle** while AWS Budgets calibrates its projection model. Treat early-month forecasted 100% pings as informational for the first 2–3 days.

---

## Related runbooks

- `0002-aws-budget-alerts-to-slack` — End-to-end manual procedure for wiring AWS Budgets to Slack via SNS + AWS Chatbot.
- `0004-budget-alert-thresholds` — Fresh-account threshold baseline (80% actual + 100% forecasted) and when to revise it for mature workloads.
