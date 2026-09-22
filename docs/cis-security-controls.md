# AWS Foundational / CIS Security Controls

This documents the controls enabled by the Terraform `security` module
(`terraform/modules/security`) plus supporting controls elsewhere in the code,
mapped to the assignment's requirement to "enable and configure AWS Foundational
Security Best Practices / CIS-aligned security controls."

## Controls enabled (what & where)

| Control | AWS service | CIS / FSBP reference | Code |
|---|---|---|---|
| Management-event audit logging | **CloudTrail** (multi-region, log-file validation) | CIS 3.1 / CloudTrail.1 | `security/cloudtrail.tf` |
| Trail bucket hardened | S3 (KMS SSE, versioning, public-access block, least-priv policy) | CIS 3.3 / S3.* | `security/cloudtrail.tf` |
| Configuration recording + rules | **AWS Config** recorder + delivery + 3 managed rules | Config.1 | `security/config.tf` |
| Threat detection | **GuardDuty** detector | GuardDuty.1 | `security/detective.tf` |
| Aggregated posture + benchmarks | **Security Hub** + FSBP v1.0.0 + CIS v1.4.0 subscriptions | — | `security/detective.tf` |
| Container image scanning | **ECR** scan-on-push + KMS + lifecycle | ECR.1/ECR.3 | `security/ecr.tf` |
| Default EBS encryption | EC2 account setting | EC2.7 | `security/account.tf` |
| Strong IAM password policy | IAM | CIS 1.8–1.11 | `security/account.tf` |
| Network traffic logging | **VPC Flow Logs** → CloudWatch | CIS 3.9 / EC2.6 | `modules/vpc/main.tf` |
| Secrets encrypted at rest | **KMS** envelope encryption for EKS secrets | EKS.3 | `modules/eks/main.tf` |
| Control-plane audit logs | EKS logging → CloudWatch | EKS.8 | `modules/eks/main.tf` |
| Private worker nodes | VPC design | EC2.* | `modules/vpc/main.tf` |
| Least-privilege IAM roles | IAM | IAM.* | `modules/iam/main.tf` |

## AWS Config managed rules enabled
- `s3-bucket-public-read-prohibited`
- `encrypted-volumes`
- `iam-user-mfa-enabled`

(Extendable — add more rules or attach an AWS-managed **conformance pack** for
the full CIS benchmark.)

## Evidence / how to verify (for the live demo)

```bash
# CloudTrail is logging and validated
aws cloudtrail describe-trails --query 'trailList[].{Name:Name,Multi:IsMultiRegionTrail,Validation:LogFileValidationEnabled}'
aws cloudtrail get-trail-status --name contact-app-dev-trail

# GuardDuty enabled
aws guardduty list-detectors

# Security Hub + enabled standards
aws securityhub get-enabled-standards

# AWS Config recording
aws configservice describe-configuration-recorder-status
aws configservice describe-compliance-by-config-rule

# EBS default encryption on
aws ec2 get-ebs-encryption-by-default

# EKS secret encryption + logging
aws eks describe-cluster --name contact-app-dev \
  --query 'cluster.{Enc:encryptionConfig,Logging:logging}'
```

Capture screenshots of: Security Hub summary (security score + failed
controls), GuardDuty findings page, Config rules compliance, and the EKS
console "Logging" and "Encryption" panels.

## Findings & remediation notes

| Finding (typical on a fresh account) | Status | Notes |
|---|---|---|
| Root account MFA / no access keys | 📝 Manual | Cannot be done in Terraform; document that root MFA is enabled + no root keys. |
| EKS public endpoint open to `0.0.0.0/0` | 🔧 Remediate | Set `cluster_public_access_cidrs` to your `/32`. Left open by default only for grading convenience. |
| No HTTPS/TLS on the load balancer | 📝 Accepted (assignment) | Needs an ACM cert + domain; documented, out of scope for the demo. |
| Security Hub CIS "hardware MFA for root" | ❌ Cannot remediate via IaC | Requires console/root actions; noted as a known residual. |
| GuardDuty + Security Hub not enabled | ❌ Cannot remediate on this account | The AWS account is on the **free plan**, which blocks GuardDuty/Security Hub subscriptions (`SubscriptionRequiredException`) and non-free-tier EC2 types. Gated behind `enable_threat_detection=false`. On a paid-plan account, set it to `true` to enable both (the Terraform is already written and validated). |
| Worker nodes use `t3.small` (not `t3.medium`) | 🔧 Account-driven | The free plan only permits free-tier-eligible instance types, so `node_instance_types` is `["t3.small"]`. A paid-plan account can use `t3.medium`+. |
| Some FSBP controls need >24h of data (Config/GuardDuty) | ⏳ Time-based | Findings populate after the account has run for a while. |

## Why some findings remain
A few CIS/FSBP controls (root-account hardening, hardware MFA, org-level
settings) are **account/root-scoped** and deliberately not automatable with
workload Terraform for safety; they are listed as documented manual steps rather
than silently ignored.
