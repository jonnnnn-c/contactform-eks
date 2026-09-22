variable "project" {
  description = "Project name, used for naming and tagging."
  type        = string
  default     = "contact-app"
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-southeast-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets across."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway (cheaper) vs one per AZ (HA)."
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "EKS control plane version. Use a STANDARD_SUPPORT version (1.34/1.35/1.36) to avoid the extended-support surcharge; check with 'aws eks describe-cluster-versions'."
  type        = string
  default     = "1.36"
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "cluster_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Lock this to your IP."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_security_controls" {
  description = "Toggle the CIS/foundational security controls module (CloudTrail, Config, GuardDuty, Security Hub)."
  type        = bool
  default     = true
}

variable "budget_limit_usd" {
  description = "Monthly budget limit (USD). Alert thresholds are percentages of this."
  type        = number
  default     = 100
}

variable "budget_alert_thresholds" {
  description = "Percent-of-limit thresholds to alert on (ACTUAL spend). E.g. [10,50,80,100] on a $100 limit alerts at $10/$50/$80/$100."
  type        = list(number)
  default     = [10, 50, 80, 100]
}

variable "budget_notification_emails" {
  description = "Emails to notify when the budget threshold is crossed. Empty = no budget created."
  type        = list(string)
  default     = []
}

variable "enable_threat_detection" {
  description = "Enable GuardDuty + Security Hub (needs a fully-activated AWS account)."
  type        = bool
  default     = true
}
