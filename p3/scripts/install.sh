#!/usr/bin/env bash
set -euo pipefail

echo "[P3] Updating apt metadata..."
sudo apt update

echo "[P3] Recovering apt/dpkg state if needed..."
sudo dpkg --configure -a || true
sudo apt --fix-broken install -y || true

echo "[P3] Installing base packages..."
sudo apt install -y docker.io curl git ca-certificates

echo "[P3] Enabling Docker..."
sudo systemctl enable --now docker
sudo usermod -aG docker "${USER}"

echo "[P3] Installing kubectl..."
KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
rm -f /tmp/kubectl

echo "[P3] Installing k3d..."
curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

echo "[P3] Installing Argo CD CLI (optional but useful)..."
if curl -fsSLo /tmp/argocd "https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64"; then
  sudo install -m 0755 /tmp/argocd /usr/local/bin/argocd
  rm -f /tmp/argocd
else
  echo "[P3] Warning: could not download argocd CLI (GitHub rate limit/network)."
  echo "[P3] Continuing without argocd CLI; kubectl-based workflow is unaffected."
fi

echo "[P3] Installation complete."
echo "[P3] Open a new shell or run: newgrp docker"
