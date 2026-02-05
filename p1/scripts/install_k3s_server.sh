#!/bin/bash
set -e

echo "[SERVER] Preparing system packages..."
dnf makecache
dnf install -y curl iproute net-tools

echo "[SERVER] Installing K3s server..."
curl -sfL https://get.k3s.io | sh -

echo "[SERVER] Waiting for token..."
while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
  sleep 1
done

echo "[SERVER] Copying token to /vagrant/token"
cp /var/lib/rancher/k3s/server/node-token /vagrant/token
chmod 644 /vagrant/token

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[SERVER] Installing kubectl..."
  KUBECTL_VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
  curl -L -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x /usr/local/bin/kubectl
fi

echo "[SERVER] K3s server ready"
