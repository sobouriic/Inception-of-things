#!/bin/bash
set -e

SERVER_IP="192.168.56.110"

echo "[AGENT] Waiting for server token..."

while [ ! -f /vagrant/token ]; do
  sleep 2
done

TOKEN=$(cat /vagrant/token)

echo "[AGENT] Installing K3s agent..."
curl -sfL https://get.k3s.io | \
  K3S_URL="https://${SERVER_IP}:6443" \
  K3S_TOKEN="${TOKEN}" sh -

echo "[AGENT] K3s agent installed"
