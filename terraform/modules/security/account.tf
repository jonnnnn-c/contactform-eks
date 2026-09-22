data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# CIS 1.x: strong IAM account password policy.
resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
}

# CIS 2.2.1 / FSBP EC2.7: encrypt new EBS volumes by default.
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}
