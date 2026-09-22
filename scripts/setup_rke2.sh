#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# One-shot, idempotent bootstrap for a LOCAL single-node RKE2 dev cluster.
#
#   ./setup_rke2.sh
#
# It will (skipping anything already done):
#   1. install RKE2 server           (sudo)
#   2. start & wait for the node Ready
#   3. write ~/.kube/config for your user
#   4. put kubectl (RKE2's) + helm on PATH (/usr/local/bin)
#   5. install the local-path storage provisioner (RKE2 ships none by default)
#   6. build the app image with Docker and import it into RKE2's containerd
#
# Run as your normal user (NOT with sudo in front); it calls sudo only for the
# steps that need root, so files land in your home with the right ownership.
# ---------------------------------------------------------------------------
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; BLU='\033[1;34m'; YEL='\033[0;33m'; NC='\033[0m'
step() { echo -e "\n${BLU}==> $*${NC}"; }
ok()   { echo -e "${GRN}    $*${NC}"; }
warn() { echo -e "${YEL}    $*${NC}"; }
die()  { echo -e "${RED}ERROR: $*${NC}" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
IMAGE="${IMAGE:-contact-app}"
TAG="${TAG:-0.1.0}"
RKE2_BIN="/var/lib/rancher/rke2/bin"

[[ $EUID -eq 0 ]] && die "Run as your normal user, not with sudo (the script sudo's what it needs)."
command -v sudo >/dev/null || die "sudo is required."

# --- 1. Install RKE2 --------------------------------------------------------
step "1/5  Installing RKE2 server"
if systemctl list-unit-files 2>/dev/null | grep -q '^rke2-server.service'; then
  ok "RKE2 already installed; skipping download."
else
  curl -sfL https://get.rke2.io | sudo sh -
  ok "RKE2 installed."
fi

step "      Enabling & starting rke2-server (first boot pulls images, ~2-4 min)"
sudo systemctl enable --now rke2-server.service
ok "rke2-server enabled."

# --- 2. Wait for kubeconfig + node Ready ------------------------------------
step "2/5  Waiting for the cluster to come up"
for i in $(seq 1 60); do
  [[ -f /etc/rancher/rke2/rke2.yaml ]] && break
  sleep 5; echo -n "."
done
[[ -f /etc/rancher/rke2/rke2.yaml ]] || die "Timed out waiting for kubeconfig. Check: sudo journalctl -u rke2-server -e"
echo

# --- 3. Kubeconfig for the current user -------------------------------------
step "3/5  Writing ~/.kube/config"
mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/rke2/rke2.yaml "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"
ok "kubeconfig written."

# --- 4. Put kubectl + helm on PATH ------------------------------------------
step "4/5  Ensuring kubectl + helm are on PATH"
if [[ ! -x /usr/local/bin/kubectl ]]; then
  sudo ln -sf "$RKE2_BIN/kubectl" /usr/local/bin/kubectl
  ok "Linked kubectl -> $RKE2_BIN/kubectl"
else
  ok "kubectl already on PATH."
fi
if ! command -v helm >/dev/null 2>&1; then
  step "      Installing helm"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash
  ok "helm installed."
else
  ok "helm already on PATH."
fi

export KUBECONFIG="$HOME/.kube/config"
export PATH="$PATH:$RKE2_BIN"
step "      Waiting for the node to report Ready"
sudo "$RKE2_BIN/kubectl" --kubeconfig /etc/rancher/rke2/rke2.yaml \
  wait --for=condition=Ready node --all --timeout=180s || warn "Node not Ready yet; check 'kubectl get nodes'."
kubectl get nodes -o wide || true

# --- 5. Storage provisioner --------------------------------------------------
# Unlike k3s, RKE2 ships WITHOUT a default StorageClass, so the postgres PVC
# would hang Pending forever. Install Rancher's local-path provisioner, which
# creates the "local-path" StorageClass that values-rke2.yaml expects.
LP_VER="v0.0.30"
step "5/6  Installing local-path storage provisioner ($LP_VER)"
if kubectl get storageclass local-path >/dev/null 2>&1; then
  ok "local-path StorageClass already present."
else
  kubectl apply -f "https://raw.githubusercontent.com/rancher/local-path-provisioner/${LP_VER}/deploy/local-path-storage.yaml"
  kubectl -n local-path-storage rollout status deploy/local-path-provisioner --timeout=120s ||     warn "Provisioner not ready yet; check 'kubectl -n local-path-storage get pods'."
  ok "local-path StorageClass installed."
fi

# --- 6. Build + import the app image ----------------------------------------
step "6/6  Building and importing the app image ($IMAGE:$TAG)"
if ! docker info >/dev/null 2>&1; then
  warn "Docker daemon is not running — skipping image build/import."
  warn "Start Docker, then run:  make app-image && $ROOT/scripts/setup_rke2.sh"
else
  docker build -t "$IMAGE:$TAG" "$APP_DIR"
  TARBALL="$(mktemp --tmpdir contact-app.XXXXXX.tar)"
  docker save "$IMAGE:$TAG" -o "$TARBALL"
  # RKE2 shares the k3s containerd socket path; fall back to the rke2 path.
  SOCK="/run/k3s/containerd/containerd.sock"
  [[ -S "$SOCK" ]] || SOCK="/run/rke2/containerd/containerd.sock"
  sudo "$RKE2_BIN/ctr" -a "$SOCK" -n k8s.io images import "$TARBALL"
  rm -f "$TARBALL"
  ok "Image $IMAGE:$TAG imported into RKE2 containerd."
fi

echo -e "\n${GRN}RKE2 is ready.${NC} Next:  python3 $ROOT/scripts/deploy.py local"
