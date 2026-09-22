# Local RKE2 Development Cluster

The email requires a local **RKE2** cluster running the same two-tier app before
the AWS deployment.

## Automated path (recommended)

One command installs RKE2, wires up kubectl + helm, and builds/imports the app
image (it uses `sudo` for the privileged steps and is safe to re-run):

```bash
python3 scripts/deploy.py setup-local     # or: bash scripts/setup_rke2.sh
python3 scripts/deploy.py local           # deploy the app
python3 scripts/deploy.py smoke           # verify round-trip
# ...or do setup + deploy in one go:
python3 scripts/deploy.py local --setup
```

Start Docker first (the script builds the image); if Docker is down it installs
the cluster anyway and tells you to build/import the image later.

The rest of this document is the **manual** equivalent, step by step.

## 1. Install RKE2 (single-node server)

RKE2 runs on Linux with systemd (root required for install).

```bash
# Install and start the RKE2 server
curl -sfL https://get.rke2.io | sudo sh -
sudo systemctl enable --now rke2-server.service

# Use the generated kubeconfig
mkdir -p ~/.kube
sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config

# RKE2 ships its own kubectl/helm/crictl under this path
export PATH=$PATH:/var/lib/rancher/rke2/bin
kubectl get nodes
```

RKE2 bundles `kubectl` (at the path above), `ingress-nginx`, and CoreDNS — which
is why `values-rke2.yaml` uses `ingressClassName: nginx`.

**Two things RKE2 does NOT ship** (the automated script installs both for you):

- The **`helm` CLI** — install it separately:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash
  ```
- A **default StorageClass**. Unlike k3s, RKE2 has no storage provisioner, so the
  postgres PVC (`storageClass: local-path`) would hang `Pending` forever. Install
  Rancher's local-path provisioner:
  ```bash
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
  kubectl -n local-path-storage rollout status deploy/local-path-provisioner
  ```

## 2. Make the app image available to the cluster

RKE2 uses containerd (not the Docker daemon), so import the locally-built image:

```bash
# Build with Docker
make app-image                      # -> contact-app:0.1.0

# Export and import into RKE2's containerd
docker save contact-app:0.1.0 -o /tmp/contact-app.tar
sudo /var/lib/rancher/rke2/bin/ctr -a /run/k3s/containerd/containerd.sock \
  -n k8s.io images import /tmp/contact-app.tar
```

(Alternatively push to a registry the cluster can reach and set
`app.image.repository` accordingly.)

## 3. Deploy

Either use the Python orchestrator:

```bash
python3 scripts/deploy.py local
```

…or do it by hand:

```bash
kubectl create namespace contact-app
kubectl -n contact-app create secret generic contact-app-db \
  --from-literal=DB_PASSWORD="$(openssl rand -base64 18)" \
  --from-literal=FLASK_SECRET_KEY="$(openssl rand -base64 36)"

helm upgrade --install contact-app helm/contact-app \
  -n contact-app -f helm/contact-app/values-rke2.yaml --wait
```

…or, if you prefer plain manifests over `helm install`, render them on demand
(after creating the secret above) so they never drift from the chart:

```bash
helm template contact-app helm/contact-app -n contact-app \
  -f helm/contact-app/values-rke2.yaml | kubectl -n contact-app apply -f -
```

## 4. Verify

```bash
kubectl -n contact-app get pods,svc,ingress
python3 scripts/deploy.py smoke            # automated round-trip test

# Or open in a browser via the ingress host:
echo "127.0.0.1 contact.local" | sudo tee -a /etc/hosts
# then browse http://contact.local
# (or: kubectl -n contact-app port-forward svc/contact-app 8080:80 -> http://localhost:8080)
```

## Teardown
```bash
helm uninstall contact-app -n contact-app
# Full RKE2 uninstall:
sudo /usr/local/bin/rke2-uninstall.sh
```
