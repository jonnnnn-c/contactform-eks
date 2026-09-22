# --- GuardDuty: continuous threat detection -----------------------------------
# Gated: brand-new AWS accounts return SubscriptionRequiredException until the
# account is fully activated. Set enable_threat_detection=false to skip until then.
resource "aws_guardduty_detector" "this" {
  count  = var.enable_threat_detection ? 1 : 0
  enable = true
}

# --- Security Hub + CIS / AWS Foundational Best Practices standards -----------
resource "aws_securityhub_account" "this" {
  count = var.enable_threat_detection ? 1 : 0
}

resource "aws_securityhub_standards_subscription" "fsbp" {
  count         = var.enable_threat_detection ? 1 : 0
  standards_arn = "arn:${data.aws_partition.current.partition}:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

# CIS 1.4.0 uses the region-scoped "standards/" ARN form (the ":::ruleset/" form
# is CIS 1.2.0 only; using it for 1.4.0 returns InvalidInputException).
resource "aws_securityhub_standards_subscription" "cis" {
  count         = var.enable_threat_detection ? 1 : 0
  standards_arn = "arn:${data.aws_partition.current.partition}:securityhub:${var.region}::standards/cis-aws-foundations-benchmark/v/1.4.0"
  depends_on    = [aws_securityhub_account.this]
}
