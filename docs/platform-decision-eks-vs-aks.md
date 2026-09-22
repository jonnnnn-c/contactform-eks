# Platform Decision: AWS EKS vs Azure AKS

**Decision:** Deploy to **AWS EKS**.
**Status:** Accepted.
**Context:** The email allows "either AWS EKS or Azure AKS." This record explains
why EKS was chosen for this assignment.

## Deciding factor — the assignment document is AWS-specific

The email offers a choice, but the attached detailed specification is titled
*"AWS EKS Deployment"* and every concrete requirement is an AWS construct:

- "AWS Foundational Security Best Practices / **CIS controls**"
- "**IAM** roles and policies", "**Security groups**", "**EKS** managed node groups"
- "Enable appropriate **EKS control-plane logging**"

None of these map one-to-one to Azure. Delivering AKS would mean demonstrating
Azure Policy / Microsoft Entra ID / Defender for Cloud against a checklist
written for AWS Config / IAM / Security Hub — an evaluator working through their
own document would see mismatches. Following the detailed brief means AWS.

## Practical factor — the solution is already built for AWS

The full solution (modular Terraform for VPC/IAM/EKS/security, Ansible, Helm) is
written and validated for AWS. Choosing AKS would require rebuilding all of it:
Azure provider, AKS module, ACR instead of ECR, Entra ID instead of IAM, Azure
Policy instead of Config/Security Hub — significant rework with no benefit for
this task.

## Comparison

| Factor | AWS EKS | Azure AKS |
|---|---|---|
| Matches the assignment document | Yes, exactly | No — requires re-mapping every control |
| Work already done & validated | Complete | Rebuild from scratch |
| Control-plane cost | $0.10/hr | Free (pay only for nodes) |
| New-account credits | ~$100–200 | $200 / 30 days |
| Net cost for this demo (with credits) | ~$0 | ~$0 |
| Ecosystem for the CIS/security demo | Config, GuardDuty, Security Hub, CloudTrail | Different tools, not on the checklist |

Azure AKS has a genuine edge on cost (its managed control plane is free), but
because new-account credits cover EKS anyway, the practical difference for this
short-lived demo is a couple of dollars — negligible against matching the
specification and reusing a finished, validated solution.

## Consequences

- All infrastructure code targets AWS (`terraform/` with the `hashicorp/aws`
  provider) and AWS-native security services.
- The identical application image and Helm chart run on both the local RKE2
  cluster and AWS EKS, so the app layer is portable regardless of this choice.

## When AKS would be reconsidered

- The company explicitly states a preference for Azure, **or**
- An AWS account cannot be created. In that case AKS's free control plane plus
  the $200 credit is a reasonable fallback, at the cost of rebuilding the
  infrastructure code (the app + Helm chart would carry over unchanged).
