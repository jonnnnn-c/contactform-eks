# Contact-Form on Kubernetes — RKE2 (local) + AWS EKS (Terraform + Ansible)

Intern assignment deliverable: a two-tier **Flask contact form + PostgreSQL**
application, deployed to a **local RKE2** cluster and to **AWS EKS**, with the
AWS infrastructure provisioned by **Terraform** and the application deployed by
**Ansible** — all runnable from a local workstation.

> **Note on the brief.** The attached document is a generic template that names
> a *"Federated Learning"* application; the accompanying **email** specifies the
> actual app: a *Python Flask contact form + PostgreSQL* two-tier app, on RKE2
> locally and then AWS EKS. This repo follows the **email** for *what* to deploy
> and the **document** for *how* (modular Terraform, Ansible, EKS, security
> hardening, CIS controls, full deliverables). EKS is chosen over AKS per the
> document.

## Repository layout

```
contactform-eks/
├── app/                    Flask contact-form app, Dockerfile, unit tests
├── helm/contact-app/       Helm chart (shared) + values-rke2.yaml / values-eks.yaml
├── terraform/              Modular IaC for AWS
│   └── modules/{vpc,iam,eks,security}
├── ansible/                Playbook + roles (preflight, kubeconfig, image, ns/rbac, secrets, deploy)
├── scripts/                deploy.py (orchestrator), smoke_test.py, setup_rke2.sh
├── docs/                   architecture, security checklist, CIS controls, RKE2, troubleshooting
├── Makefile
└── README.md
```

## Deliverables map (per the assignment)

| Required deliverable | Location |
|---|---|
| Terraform code (modular) | `terraform/` + `terraform/modules/*` |
| Ansible playbooks/roles | `ansible/` |
| Kubernetes manifests / Helm | `helm/contact-app/` (shared chart, per-env values) |
| README with full instructions | this file |
| AWS EKS step-by-step runbook | `docs/aws-deployment-runbook.md` |
| Architecture diagram | `docs/architecture.md` |
| Platform decision (EKS vs AKS) | `docs/platform-decision-eks-vs-aks.md` |
| Security-hardening checklist | `docs/security-hardening-checklist.md` |
| CIS/security-control config + findings | `docs/cis-security-controls.md` + `terraform/modules/security` |
| Troubleshooting notes | `docs/troubleshooting.md` |
| Git repo with clean history | this repo |

## Prerequisites

Workstation tools:

| Tool | Version (tested) | Used for |
|---|---|---|
| Python | 3.11+ | app, tests, `scripts/deploy.py` |
| Docker | 24+ | build the app image |
| Terraform | 1.6+ | AWS infrastructure |
| Ansible | 2.15+ (core) | app deployment |
| kubectl | 1.29+ | cluster access |
| Helm | 3.14+ | chart deployment |
| AWS CLI | v2 | auth + `update-kubeconfig` + ECR |
| RKE2 | current | local cluster (Linux) |

AWS setup:

- An AWS account and credentials on the workstation (`aws configure`,
  SSO, or environment variables). Verify with `aws sts get-caller-identity`.
- Permissions to create VPC/EKS/IAM/KMS/ECR/CloudTrail/Config/GuardDuty/SecurityHub.
- **No credentials are stored in this repo.** Terraform uses your local AWS
  credential chain; the DB password is generated at deploy time.

## Quick start

Everything runs through `make` (thin wrappers over `scripts/deploy.py`); run
`make help` to list every target.

**Local RKE2** (start Docker first so the image can build):
```bash
make setup-local     # install RKE2 + kubectl + helm, build/import image (uses sudo)
make local           # deploy the app
make smoke           # verify end-to-end
```

**AWS EKS** (end to end from the workstation):
```bash
# 0. Configure inputs: edit region, and LOCK cluster_public_access_cidrs to your IP/32
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# 1. Provision + deploy + smoke test, in one command
make aws
```
The deploy prints the public **NLB URL**. Teardown when done: `make aws-down`
(deletes the NLB first so its ENIs don't block VPC deletion). Local teardown is
just `helm uninstall contact-app -n contact-app`.

## Commands

| Command | What it does |
|---|---|
| `make aws` | Full AWS deploy: terraform → ansible → smoke test |
| `make aws-fresh` | Same, but destroys any existing infra first (clean slate) |
| `make aws-up` | Provision AWS infra only (terraform) |
| `make aws-app` | Deploy the app only (ansible + helm) |
| `make aws-down` | Delete the NLB, then destroy all AWS infra |
| `make local` | Deploy to the local RKE2 cluster |
| `make setup-local` | Install RKE2 + tools and build/import the image |
| `make smoke` | Smoke-test the running service (`NS=…` to override namespace) |
| `make test` | Run the Flask app unit tests |
| `make lint` | Lint the Helm chart |

Prefer raw tools? Each target just calls `python3 scripts/deploy.py <cmd>`
(see `--fresh`/`--yes` flags in `scripts/deploy.py`). Full AWS walkthrough:
**[docs/aws-deployment-runbook.md](docs/aws-deployment-runbook.md)**; local:
**[docs/local-rke2.md](docs/local-rke2.md)**.

## How the pieces fit

```
workstation ──terraform apply──▶ AWS infra (VPC/EKS/IAM/KMS/ECR/CIS controls)
workstation ──ansible──────────▶ EKS: kubeconfig ▶ image→ECR ▶ ns+RBAC ▶ secret ▶ helm release
                                          │
                        internet ──NLB──▶ Flask (Deployment+HPA) ──5432──▶ PostgreSQL (StatefulSet+EBS)
```

- **Terraform** owns infrastructure only. It is split into reusable modules
  (`vpc`, `iam`, `eks`, `security`) and toggled with variables.
- **Ansible** owns application deployment. It is idempotent: re-running
  converges the release and never rotates the DB password (keeps data intact).
- **Helm** is the Kubernetes package manager. It bundles every workload object
  (Deployment, StatefulSet, Service, ConfigMap, Secret, HPA, PDB, RBAC,
  NetworkPolicy, StorageClass) into one templated chart, so the *same chart*
  deploys to both clusters — only `values-rke2.yaml` / `values-eks.yaml` differ.
  Ansible installs it with `helm upgrade --install` (idempotent, supports rollback).

## Application

- `GET /` contact form · `POST /contact` stores a submission
- `GET /submissions` JSON of recent rows · `GET /healthz` liveness · `GET /readyz` readiness (DB ping)
- Config is 100% environment-driven (see `app/app.py`). Run tests: `make test`.

## Accessing PostgreSQL

The commands are **the same for local RKE2 and AWS EKS** — `kubectl` talks to
whichever cluster your kubeconfig currently points at. On EKS, first run
`aws eks update-kubeconfig --name contact-app-dev --region <your-region>`
(the deploy does this for you). Reference values: namespace `contact-app`,
pod `contact-app-postgres-0`, database `contacts`, user `contact`.

**Option 1 — psql inside the DB pod (nothing to install locally):**
```bash
kubectl -n contact-app exec -it contact-app-postgres-0 -- psql -U contact -d contacts
# then, at the psql prompt:
#   \dt                        list tables
#   SELECT * FROM submissions; view stored form entries
#   \q                         quit
```

**Get the DB password** (generated at deploy time, stored in a Secret):
```bash
kubectl -n contact-app get secret contact-app-db \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo
```

**Option 2 — connect from your laptop with a local `psql` / GUI (e.g. DBeaver):**
```bash
# Terminal 1: forward the DB port to localhost (leave running)
kubectl -n contact-app port-forward svc/contact-app-postgres 5432:5432

# Terminal 2: connect (uses the password from the command above)
PGPASSWORD="$(kubectl -n contact-app get secret contact-app-db \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d)" \
  psql -h 127.0.0.1 -p 5432 -U contact -d contacts
```

**Handy queries** (run at the `psql` prompt; table `submissions` =
`id, name, email, message, created_at`):
```sql
-- total number of submissions
SELECT count(*) FROM submissions;

-- 10 most recent (message trimmed for readability)
SELECT id, name, email, left(message, 50) AS message, created_at
FROM submissions ORDER BY created_at DESC LIMIT 10;

-- submissions per day
SELECT date(created_at) AS day, count(*)
FROM submissions GROUP BY day ORDER BY day DESC;

-- find submissions from a given email domain
SELECT id, name, email, created_at
FROM submissions WHERE email ILIKE '%@example.com';
```
Run one without opening a shell (handy for the demo):
```bash
kubectl -n contact-app exec -it contact-app-postgres-0 -- \
  psql -U contact -d contacts -c "SELECT count(*) FROM submissions;"
```

> The database is **never** exposed publicly (ClusterIP + NetworkPolicy) — these
> commands tunnel through the Kubernetes API, so no inbound DB port is opened.

## Security

See **[docs/security-hardening-checklist.md](docs/security-hardening-checklist.md)**
and **[docs/cis-security-controls.md](docs/cis-security-controls.md)**. Highlights:
non-root read-only containers, PSA `restricted`, NetworkPolicies, least-priv IAM,
KMS-encrypted secrets/EBS, private nodes, CloudTrail/Config/GuardDuty/Security Hub,
ECR scan-on-push, generated secrets (nothing sensitive in git).

> On EKS the app is exposed with a **Network Load Balancer** (a `type:
> LoadBalancer` Service), which EKS's built-in cloud controller provisions
> automatically — no extra controller needed. The deploy prints the public URL.
> To use an ALB Ingress instead, install the AWS Load Balancer Controller and
> set `ingress.enabled=true` in `values-eks.yaml`.

## Live demo checklist

1. `aws sts get-caller-identity` — you're on the workstation, authenticated.
2. `make aws-fresh` — destroy → provision → deploy → smoke, one command
   (or step through: `make aws-up` then `make aws-app`).
3. Open the printed **NLB URL** in a browser, submit the form, then refresh
   `/submissions` — shows the full app → PostgreSQL round-trip.
4. `kubectl get pods,svc` — the running two-tier stack.
5. Console: Security Hub score, GuardDuty, AWS Config, CloudTrail, EKS
   encryption/logging (commands in `docs/cis-security-controls.md`).
6. `make aws-down` then `make aws` — proves it's fully reproducible.
