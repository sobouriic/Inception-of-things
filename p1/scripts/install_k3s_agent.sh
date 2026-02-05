#!/bin/bash
set -e

SERVER_IP="192.168.56.110"

echo "[AGENT] Preparing system packages..."
dnf makecache
dnf install -y curl iproute net-tools

echo "[AGENT] Waiting for server token..."

while [ ! -f /vagrant/token ]; do
  sleep 2
done

TOKEN=$(cat /vagrant/token)

echo "[AGENT] Waiting for K3s API on ${SERVER_IP}:6443..."
until timeout 1 bash -c "cat < /dev/null > /dev/tcp/${SERVER_IP}/6443" 2>/dev/null; do
  sleep 2
done

echo "[AGENT] Installing K3s agent..."
curl -sfL https://get.k3s.io | \
  K3S_URL="https://${SERVER_IP}:6443" \
  K3S_TOKEN="${TOKEN}" sh -

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[AGENT] Installing kubectl..."
  KUBECTL_VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
  curl -L -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x /usr/local/bin/kubectl
fi

echo "[AGENT] K3s agent installed"
