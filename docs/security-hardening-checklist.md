# Security Hardening Checklist

Legend: ✅ implemented in this repo · 🔧 configurable · 📝 documented recommendation

## No hard-coded credentials
- ✅ No AWS keys in code — provider uses the workstation's AWS credential chain.
- ✅ DB password generated at deploy time by Ansible, stored only in a K8s Secret (`ansible/roles/secrets`).
- ✅ `FLASK_SECRET_KEY` generated, never committed.
- ✅ `.gitignore` excludes `*.tfvars`, `*.tfstate`, `.terraform/`.
- ✅ App reads all config from env (`app/app.py`), so no secrets in the image.

## IAM least privilege
- ✅ Separate cluster role (`AmazonEKSClusterPolicy` only) and node role (worker + CNI + ECR read-only + SSM).
- ✅ OIDC provider created for IRSA so workloads/add-ons get scoped roles instead of node-wide permissions.
- ✅ Strong IAM account password policy (14 chars, rotation, reuse prevention).

## Network
- ✅ Worker nodes in **private** subnets; only the NLB/NAT live in public subnets.
- ✅ VPC Flow Logs enabled to CloudWatch.
- 🔧 EKS public API endpoint restricted via `cluster_public_access_cidrs` (default `0.0.0.0/0` — **lock to your IP**).
- ✅ Kubernetes **NetworkPolicies**: default-deny ingress; DB reachable only from web pods.
- ✅ No SSH to nodes — debugging via SSM (`AmazonSSMManagedInstanceCore`), no port 22 open.

## Kubernetes workload hardening
- ✅ Containers run as **non-root** (`runAsNonRoot`, uid 10001 app / 999 postgres).
- ✅ `readOnlyRootFilesystem: true` on the web container (writable `/tmp` via emptyDir).
- ✅ `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault`.
- ✅ Namespace enforces **Pod Security Admission `restricted`** (`ansible/roles/namespace_rbac`).
- ✅ Minimal **RBAC** Role/RoleBinding; ServiceAccount token not mounted (`automountServiceAccountToken: false`).
- ✅ **Resource requests/limits** on every container.
- ✅ Liveness (`/healthz`) and readiness (`/readyz`) probes.
- ✅ **PodDisruptionBudget** + **HPA** for availability.

## Images
- ✅ Trusted base image (`python:3.12-slim`, official `postgres:16-alpine`).
- ✅ Multi-stage build → smaller runtime, no build toolchain shipped.
- ✅ ECR **scan-on-push** enabled; lifecycle policy prunes old images.
- 📝 Recommend pinning base images by digest and running Trivy in CI.

## Data protection / encryption
- ✅ EKS secrets encrypted at rest with **KMS** (envelope encryption, key rotation on).
- ✅ **EBS encryption by default** enabled account-wide.
- ✅ CloudTrail and AWS Config S3 buckets encrypted (KMS), versioned, public access blocked.
- 🔧 Add TLS/HTTPS (ACM cert on the load balancer) — documented, cert not provisioned in the assignment.

## Observability / audit
- ✅ All EKS control-plane log types enabled → CloudWatch (`api, audit, authenticator, controllerManager, scheduler`).
- ✅ CloudTrail multi-region with log-file validation.
- ✅ GuardDuty + Security Hub (FSBP + CIS standards).

## Dependencies
- ✅ Pinned Python deps (`app/requirements.txt`), current Flask/gunicorn.
- ✅ Pinned Terraform provider (`~> 5.60`) and EKS version (1.30).
- 📝 Recommend Dependabot/renovate for ongoing updates.
