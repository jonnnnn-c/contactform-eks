# AWS EKS Deployment Runbook

Every command to deploy the app to AWS EKS from a clean slate, in order. Run
them yourself from a terminal. The Terraform code fixes (AL2023 node AMI,
gated GuardDuty/Security Hub) are already applied.

## One-command option (recommended)

The whole flow is wrapped in the Python orchestrator. From a clean slate:

```bash
export PATH="$HOME/.local/bin:$PATH"
cd ~/Desktop/NextLab/contactform-eks
python3 scripts/deploy.py aws --fresh      # destroy -> apply -> deploy -> smoke
```

- It runs `terraform destroy` (clean slate) -> `init` -> `apply` -> `ansible`
  -> smoke test.
- **You still confirm the apply** by typing `yes` (it shows the plan first).
  Add `--yes` to auto-approve, or drop `--fresh` if nothing exists yet.
- Tear down afterwards: `python3 scripts/deploy.py aws-down`.

The step-by-step commands below do exactly the same thing, if you prefer to run
each one yourself.

> **PATH:** the deploy tools live in `~/.local/bin` (terraform, aws, ansible)
> and `/usr/local/bin` (kubectl, helm). Start every terminal with:
> ```bash
> export PATH="$HOME/.local/bin:$PATH"
> ```

---

## 0. Prerequisites (already installed on this machine)
| Tool | Check |
|---|---|
| terraform | `terraform version` |
| aws CLI    | `aws --version` |
| ansible    | `ansible --version` |
| kubectl / helm / docker | `kubectl version --client`, `helm version`, `docker info` |

AWS credentials are configured (`aws configure`); verify:
```bash
aws sts get-caller-identity        # should print your account + user
```

---

## 1. Start from scratch — destroy any existing infra
If a previous (partial) apply left resources, remove them first so you begin clean:
```bash
export PATH="$HOME/.local/bin:$PATH"
cd ~/Desktop/NextLab/contactform-eks/terraform
terraform destroy                  # review the list, type: yes
```
Wait for `Destroy complete!`. This stops all billing.

---

## 2. Provision the infrastructure
```bash
terraform init                     # first time / after module changes
terraform plan                     # review: ~59 resources to add
terraform apply                    # type: yes    (~15-20 min; EKS is the slow part)
```
Key inputs live in `terraform.tfvars` (region, your IP lock, node size, budget,
`enable_threat_detection`). Edit before apply if needed.

When it finishes, note the outputs:
```bash
terraform output                   # cluster_name, ecr_repository_url, configure_kubectl
```

---

## 3. Connect kubectl to the new cluster
```bash
aws eks update-kubeconfig --region ap-southeast-1 --name contact-app-dev
kubectl get nodes                  # should list 2 Ready nodes
```

---

## 4. Deploy the application (Ansible → build image, push to ECR, helm install)
```bash
cd ../ansible
ansible-playbook site.yml
```
This runs: preflight checks → kubeconfig → build & push image to ECR →
namespace + PSA labels → generate DB secret → helm upgrade --install.

---

## 5. Verify
```bash
kubectl -n contact-app get pods,svc
python3 ../scripts/deploy.py smoke          # end-to-end round-trip test
```
The app is exposed by a public **NLB**. Get its URL (DNS is live ~2 min after
create) and open it in a browser:
```bash
echo "http://$(kubectl -n contact-app get svc contact-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```
Offline fallback (no public URL needed): `kubectl -n contact-app port-forward
svc/contact-app 8080:80` then browse http://localhost:8080

---

## 6. Full CIS controls (once the account is fully activated)
New accounts can't subscribe to GuardDuty/Security Hub immediately. After a few
hours:
```bash
# edit terraform/terraform.tfvars:  enable_threat_detection = true
terraform apply
```

---

## 7. Tear down (stop billing when done / demo the recreate)
```bash
# Deletes the app's NLB first (so its ENIs don't block VPC deletion),
# then destroys all infrastructure.
python3 scripts/deploy.py aws-down       # type: yes at the prompt
```

---

## Notes / gotchas
- **`terraform apply` is resumable** — if it stops midway, just run it again; it
  only creates what's missing.
- **Node group AMI**: must be `AL2023_x86_64_STANDARD` (set in `modules/eks`).
  The old AL2 family is retired and fails on current EKS versions.
- **GuardDuty/Security Hub `SubscriptionRequiredException`** = account not fully
  activated yet. Keep `enable_threat_detection = false` until it is.
- **Confirm the budget email** AWS sends so the $10 cost alarm activates.
- See `troubleshooting.md` for more failure modes.
