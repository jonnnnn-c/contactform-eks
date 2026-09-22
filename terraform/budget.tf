# Cost safety net: a monthly budget that emails you at escalating thresholds so
# you never silently burn through your AWS credits. With a $100 limit and
# thresholds [10,50,80,100], you get alerts at $10, $50, $80 and $100 of spend —
# the $100 alert is your "credits nearly depleted" warning (≈$20 left of $120).
# Created only when at least one notification email is provided.
resource "aws_budgets_budget" "monthly" {
  count        = length(var.budget_notification_emails) > 0 ? 1 : 0
  name         = "${local.name}-monthly-cost"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Alert on ACTUAL spend at each threshold.
  dynamic "notification" {
    for_each = toset(var.budget_alert_thresholds)
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = var.budget_notification_emails
    }
  }

  # Early heads-up when FORECASTED to reach the limit.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_notification_emails
  }
}
