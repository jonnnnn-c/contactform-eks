#!/usr/bin/env python3
"""
Workstation deployment orchestrator for the contact-form app.

One entrypoint for the whole assignment workflow:

    ./deploy.py aws-up        # terraform apply  -> provision EKS + security
    ./deploy.py aws-app       # ansible-playbook -> build/push image + deploy app
    ./deploy.py aws           # apply -> deploy -> smoke, end to end
    ./deploy.py aws --fresh    # destroy first, then the full flow (clean slate)
    ./deploy.py aws --yes      # skip the interactive apply confirmation
    ./deploy.py setup-local   # install RKE2 + tools + build/import image (sudo)
    ./deploy.py local          # deploy the app to the local RKE2 cluster
    ./deploy.py local --setup  # setup-local, then deploy, in one go
    ./deploy.py smoke         # run the smoke test against the running service
    ./deploy.py aws-down       # terraform destroy

This is intentionally a thin, transparent wrapper around terraform, ansible and
helm so the exact commands are visible and reproducible (and printable for the
live demo). It shells out rather than hiding logic.
"""
import argparse
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TF_DIR = os.path.join(ROOT, "terraform")
ANSIBLE_DIR = os.path.join(ROOT, "ansible")
CHART = os.path.join(ROOT, "helm", "contact-app")
APP_DIR = os.path.join(ROOT, "app")


def run(cmd, cwd=None, env=None):
    print(f"\n\033[1;34m$ {' '.join(cmd)}\033[0m  (cwd={cwd or os.getcwd()})")
    subprocess.run(cmd, cwd=cwd, env=env, check=True)


def require(*tools):
    missing = [t for t in tools if shutil.which(t) is None]
    if missing:
        sys.exit(f"Missing required tools on PATH: {', '.join(missing)}")


def _tf(args, action):
    """Run a terraform action. apply/destroy are INTERACTIVE by default (you see
    the plan and type 'yes'); pass --yes to auto-approve for hands-off runs."""
    cmd = ["terraform", action]
    if action in ("apply", "destroy") and getattr(args, "yes", False):
        cmd.append("-auto-approve")
    run(cmd, cwd=TF_DIR)


def _tf_output(name):
    """Return a terraform output value, or '' if unavailable."""
    p = subprocess.run(["terraform", "output", "-raw", name],
                       cwd=TF_DIR, capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else ""


def _cleanup_k8s_loadbalancers():
    """Delete the app's LoadBalancer Service before 'terraform destroy'.

    The Service provisions an AWS NLB whose ENIs live in the VPC subnets; if it
    survives, terraform can't delete the subnets/VPC and destroy hangs/fails.
    Best-effort: silently skips if the cluster is already gone or unreachable.
    """
    if shutil.which("kubectl") is None:
        return
    name, region = _tf_output("cluster_name"), _tf_output("region")
    if not name or not region:
        return
    print("\nRemoving app load balancer (NLB) before destroy...")
    subprocess.run(["aws", "eks", "update-kubeconfig", "--name", name,
                    "--region", region], check=False)
    subprocess.run(["kubectl", "-n", "contact-app", "delete", "svc",
                    "contact-app", "--ignore-not-found", "--timeout=180s"],
                   check=False)
    time.sleep(30)  # let AWS deprovision the NLB and release its ENIs


def aws_up(args):
    require("terraform")
    run(["terraform", "init"], cwd=TF_DIR)
    if getattr(args, "fresh", False):
        print("\n--fresh: destroying any existing infrastructure first...")
        _cleanup_k8s_loadbalancers()
        _tf(args, "destroy")
    _tf(args, "apply")


def aws_app(_):
    require("ansible-playbook")
    run(["ansible-playbook", "site.yml"], cwd=ANSIBLE_DIR)


def aws(args):
    """Full AWS flow: (optional destroy) -> terraform apply -> ansible deploy
    -> smoke test. Everything is visible and you confirm the apply yourself."""
    aws_up(args)
    aws_app(args)
    if not getattr(args, "no_smoke", False):
        try:
            smoke(args)
        except subprocess.CalledProcessError:
            print("Smoke test failed. Inspect with: "
                  "kubectl -n contact-app get pods")


def aws_down(args):
    require("terraform")
    _cleanup_k8s_loadbalancers()
    _tf(args, "destroy")


def setup_local(_):
    """Bootstrap a local single-node RKE2 cluster (installs RKE2, kubectl, helm
    and imports the app image). Delegates to scripts/setup_rke2.sh because the
    RKE2 install needs root; that script sudo's the privileged steps itself."""
    script = os.path.join(ROOT, "scripts", "setup_rke2.sh")
    run(["bash", script])


def local(args):
    """Deploy to a local RKE2 cluster with helm using values-rke2.yaml."""
    if getattr(args, "setup", False):
        setup_local(args)
    if shutil.which("helm") is None or shutil.which("kubectl") is None:
        sys.exit(
            "helm/kubectl not found. Run 'python3 scripts/deploy.py setup-local' "
            "first (installs RKE2 + tools), or re-run with '--setup'."
        )
    require("helm", "kubectl")
    ns = args.namespace
    run(["kubectl", "create", "namespace", ns,
         "--dry-run=client", "-o", "yaml"])
    subprocess.run(
        ["kubectl", "apply", "-f", "-"],
        input=(
            f"apiVersion: v1\nkind: Namespace\nmetadata:\n  name: {ns}\n"
        ).encode(),
        check=True,
    )
    # Create the DB secret once (kept on re-runs).
    existing = subprocess.run(
        ["kubectl", "-n", ns, "get", "secret", args.secret_name],
        capture_output=True,
    )
    if existing.returncode != 0:
        import secrets as pysecrets
        pw = pysecrets.token_urlsafe(18)
        key = pysecrets.token_urlsafe(36)
        run(["kubectl", "-n", ns, "create", "secret", "generic",
             args.secret_name,
             f"--from-literal=DB_PASSWORD={pw}",
             f"--from-literal=FLASK_SECRET_KEY={key}"])
    else:
        print(f"Secret {args.secret_name} already exists; keeping it.")
    run(["helm", "upgrade", "--install", "contact-app", CHART,
         "-n", ns,
         "-f", os.path.join(CHART, "values-rke2.yaml"),
         "--set", f"secret.name={args.secret_name}",
         "--wait", "--timeout", "5m"])
    run(["kubectl", "-n", ns, "get", "pods,svc,ingress", "-o", "wide"])


def smoke(args):
    require("kubectl")
    smoke_script = os.path.join(ROOT, "scripts", "smoke_test.py")
    run([sys.executable, smoke_script, "-n", args.namespace])


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("-n", "--namespace", default="contact-app")
    p.add_argument("--secret-name", default="contact-app-db")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, fn in [
        ("aws-up", aws_up), ("aws-app", aws_app), ("aws", aws),
        ("aws-down", aws_down), ("setup-local", setup_local),
        ("local", local), ("smoke", smoke),
    ]:
        sp = sub.add_parser(name)
        if name == "local":
            sp.add_argument("--setup", action="store_true",
                            help="Bootstrap RKE2 (setup-local) before deploying.")
        if name in ("aws", "aws-up"):
            sp.add_argument("--fresh", action="store_true",
                            help="terraform destroy before apply (clean slate).")
            sp.add_argument("--yes", action="store_true",
                            help="auto-approve terraform (skip the 'yes' prompt).")
        if name == "aws":
            sp.add_argument("--no-smoke", action="store_true",
                            help="skip the post-deploy smoke test.")
        if name == "aws-down":
            sp.add_argument("--yes", action="store_true",
                            help="auto-approve terraform destroy.")
        sp.set_defaults(func=fn)
    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
