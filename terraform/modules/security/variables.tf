variable "name" { type = string }
variable "region" { type = string }

variable "enable_threat_detection" {
  description = "Enable GuardDuty + Security Hub. Disable on brand-new accounts that cannot subscribe yet."
  type        = bool
  default     = true
}
