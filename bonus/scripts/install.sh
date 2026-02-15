#!/usr/bin/env bash
set -euo pipefail

echo "[BONUS] Installing tools for GitLab bonus..."
sudo apt update
sudo apt install -y curl git jq apt-transport-https ca-certificates gnupg

if ! command -v helm >/dev/null 2>&1; then
  echo "[BONUS] Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  echo "[BONUS] Helm already installed."
fi

echo "[BONUS] Done."
