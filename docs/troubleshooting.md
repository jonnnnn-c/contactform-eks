# Troubleshooting Notes

## Terraform

| Symptom | Cause / Fix |
|---|---|
| `Error: creating EKS Cluster ... AccessDenied` | Your IAM principal lacks EKS/IAM permissions. Use an admin/deploy role. |
| `UnauthorizedOperation` on VPC/EC2 | Same — check `aws sts get-caller-identity` and attached policies. |
| Node group stuck `CREATING` then fails | Usually subnets can't reach the internet. Confirm NAT gateway + private route tables (this repo wires them automatically). |
| `Error: reading EKS Add-On version` | Add-on not available for the chosen `kubernetes_version`; bump/adjust `kubernetes_version`. |
| `Requested AMI for this version X is not supported` / console "Kubernetes version no longer supported" | The EKS version reached end-of-life; its node AMIs are withdrawn. Set `kubernetes_version` to a **STANDARD_SUPPORT** version (check `aws eks describe-cluster-versions`). Avoid extended-support versions — they add ~$0.50/hr to the control plane. A running EOL cluster must be **recreated** (`deploy.py aws --fresh`) since you can't skip multiple minor upgrades. |
| Destroy hangs on the VPC | ENIs from the app's NLB are left behind. Use `python3 scripts/deploy.py aws-down`, which deletes the LoadBalancer Service (removing the NLB) **before** `terraform destroy`. |
| State lock error | Someone/another run holds the DynamoDB lock (if using the S3 backend). Wait or `terraform force-unlock <id>`. |

## kubectl / EKS access

| Symptom | Fix |
|---|---|
| `error: You must be logged in to the server (Unauthorized)` | Re-run `aws eks update-kubeconfig`; ensure your IAM identity has an EKS access entry (this cluster uses `API_AND_CONFIG_MAP`). |
| `kubectl` times out | Public endpoint CIDR (`cluster_public_access_cidrs`) doesn't include your IP. |

## Application / pods

| Symptom | Fix |
|---|---|
| Web pod `CrashLoopBackOff` | Check `kubectl logs`. Most often the DB secret is missing — the `secrets` role must run before `app_deploy`. |
| `/readyz` returns 503 | DB not reachable yet. Check the postgres StatefulSet is `Running` and the `-postgres` Service resolves. First start can take ~30s. |
| Web pod `CreateContainerConfigError` | Secret `contact-app-db` not found in the namespace. Create it (see local-rke2.md) or run the Ansible `secrets` role. |
| Postgres pod `Pending` / PVC `Pending`, `storageclass "local-path" not found` | RKE2 ships **no** default StorageClass (unlike k3s). Install the local-path provisioner (the `setup-local` script does this automatically): `kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml`. On EKS the `gp3` class comes from the EBS CSI add-on. |
| PSA denies the pod (`violates PodSecurity "restricted"`) | The namespace enforces `restricted`. Both containers already comply; if you edit them keep `runAsNonRoot`, dropped caps, seccomp, no privilege escalation. |
| `ImagePullBackOff` on EKS | Image not pushed to ECR or node role missing ECR read. Run the `ecr_image` role; node role has `AmazonEC2ContainerRegistryReadOnly`. |
| `ImagePullBackOff` on RKE2 | Image not imported into containerd — see local-rke2.md step 2 (RKE2 doesn't use the Docker daemon). |

## Ansible

| Symptom | Fix |
|---|---|
| `Missing required tools` in preflight | Install `aws`, `kubectl`, `helm` (and `docker` if `build_image=true`). |
| ECR URL empty | Run `terraform apply` first, or pass `-e ecr_repo_url=<url>`. |
| Helm task reports `changed` every run | Expected for `upgrade --install`; the play still converges. Real drift shows in `helm diff`. |

## Load balancer on EKS

- The app is exposed by a **`type: LoadBalancer` Service** (annotation
  `aws-load-balancer-type: "nlb"`), which EKS's built-in cloud controller turns
  into a public **NLB** automatically — no AWS Load Balancer Controller needed.
- `EXTERNAL-IP` stuck `<pending>`: the public subnets must be tagged
  `kubernetes.io/role/elb=1` (this repo does that). Check with
  `kubectl -n contact-app describe svc contact-app`.
- To use an **ALB Ingress** instead, install the AWS Load Balancer Controller
  and set `ingress.enabled=true` in `values-eks.yaml`.
