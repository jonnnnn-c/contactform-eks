# AWS Foundational / CIS Security Controls

This documents the controls enabled by the Terraform `security` module
(`terraform/modules/security`) plus supporting controls elsewhere in the code,
mapped to the assignment's requirement to "enable and configure AWS Foundational
Security Best Practices / CIS-aligned security controls."

## Controls enabled (what & where)

| Control | AWS service | CIS / FSBP reference | Code |
|---|---|---|---|
| Management-event audit logging | **CloudTrail** (multi-region, log-file validation, **KMS CMK-encrypted**, streamed to **CloudWatch Logs**) | CIS 3.1 / CloudTrail.1/.2/.5 | `security/cloudtrail.tf` |
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

## Findings & remediation (Security Hub CSPM / GuardDuty / Config, `ap-southeast-1`)

Security Hub flagging baseline issues on a fresh account is expected — surfacing
them is exactly the evidence the assignment asks for. The findings are triaged
below. (Note: the security score and some controls need ~30 min to first
populate after the controls are enabled.)

### Remediated
| Finding | Fix |
|---|---|
| CloudTrail should be encrypted at rest with a CMK (CloudTrail.2) | Added a dedicated KMS key; `kms_key_id` on the trail (`security/cloudtrail.tf`). |
| CloudTrail should integrate with CloudWatch Logs (CloudTrail.5) | Added a log group + IAM role; `cloud_watch_logs_*` on the trail (`security/cloudtrail.tf`). |
| Hardware MFA for the root user (CRITICAL) | Enabled a virtual MFA device on root (manual — MFA activation can't be done in Terraform). |
| `iam-user-mfa-enabled` (deploy user) | Enabled a virtual MFA device on the `nextlab_deploy` user. |
| EKS public API endpoint | Locked to a single `/32` via `cluster_public_access_cidrs` (not `0.0.0.0/0`). |

### Accepted — account/root scope (owner responsibility, not the deploy identity)
| Finding | Why accepted |
|---|---|
| AWS support role not created | Account-owner task; not part of the Terraform-deployed app infra. |
| GuardDuty: API calls made with root credentials | Came from browsing the console as root; addressed by using an IAM user going forward. |

### Accepted — false positives in context
| Finding | Why |
|---|---|
| GuardDuty: `DescribeCluster` from a Kali Linux computer | Legitimate — I deploy from a Kali workstation; not a threat. |

### Deliberate design choice
| Finding | Rationale |
|---|---|
| Config.1 — Config should use the service-linked role | I used an explicit least-privilege **custom** IAM role for transparency and clean destroy/recreate (the service-linked role is account-global and lingers after `destroy`). Documented trade-off — Config is enabled and recording all supported resources. |

### Deferred — lower-risk, timeboxed
| Finding | Why deferred |
|---|---|
| S3 buckets: require TLS / server-access logging / MFA delete | Internal log buckets only; low risk. |
| NLB should use encrypted transport (TLS) | Needs an ACM certificate + a domain — out of scope for the demo. |
| VPC flow logging on the default VPC | The account's **unused default VPC**; my Terraform-managed VPC has flow logs. |
| Base-image OS CVE (ECR scan, e.g. zlib) | Debian package in `python:3.12-slim`; cleared by rebasing on an updated base image. |

Given the 1–2 week assignment window alongside concurrent university coursework,
the highest-impact controls were prioritised and these lower-severity items were
consciously deferred and documented rather than silently skipped.
