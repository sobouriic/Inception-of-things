#!/bin/bash
set -e

TOKEN_FILE="/vagrant/confs/k3s_token"
SERVER_IP_DEFAULT="192.168.56.110"
SERVER_IP=""

if [ -f /etc/centos-release ] && grep -q "CentOS Linux release 7" /etc/centos-release; then
  echo "[AGENT] Fixing CentOS 7 repositories..."
  sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-Base.repo
  sed -i 's|^#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-Base.repo
fi

echo "[AGENT] Preparing system packages..."
if command -v dnf >/dev/null 2>&1; then
  dnf makecache
  dnf install -y curl iproute net-tools
else
  yum clean all
  yum makecache
  yum install -y curl iproute net-tools
fi

echo "[AGENT] Waiting for server IP metadata..."
for _ in $(seq 1 150); do
  if [ -f /vagrant/server_ip ]; then
    SERVER_IP="$(cat /vagrant/server_ip)"
    break
  fi
  sleep 2
done

if [ -z "${SERVER_IP}" ] && [ -n "${K3S_SERVER_IP:-}" ]; then
  SERVER_IP="${K3S_SERVER_IP}"
fi

if [ -z "${SERVER_IP}" ]; then
  SERVER_IP="${SERVER_IP_DEFAULT}"
fi

echo "[AGENT] Using server IP: ${SERVER_IP}"

echo "[AGENT] Waiting for K3s API on ${SERVER_IP}:6443..."
until timeout 1 bash -c "cat < /dev/null > /dev/tcp/${SERVER_IP}/6443" 2>/dev/null; do
  sleep 2
done

if [ -n "${K3S_SHARED_TOKEN:-}" ]; then
  echo "[AGENT] Using K3S_SHARED_TOKEN from environment."
else
  echo "[AGENT] Waiting for K3s token..."
  for _ in $(seq 1 150); do
    if [ -f "${TOKEN_FILE}" ]; then
      K3S_SHARED_TOKEN="$(cat "${TOKEN_FILE}")"
      break
    fi
    sleep 2
  done
fi

if [ -z "${K3S_SHARED_TOKEN}" ]; then
  echo "[AGENT] ERROR: K3s token not found. Ensure ${TOKEN_FILE} exists or set K3S_SHARED_TOKEN."
  exit 1
fi

echo "[AGENT] Installing K3s agent..."
curl -sfL https://get.k3s.io | \
  K3S_URL="https://${SERVER_IP}:6443" \
  K3S_TOKEN="${K3S_SHARED_TOKEN}" \
  INSTALL_K3S_EXEC="agent --node-ip=192.168.56.111" \
  sh -

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[AGENT] Installing kubectl..."
  KUBECTL_VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
  curl -L -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x /usr/local/bin/kubectl
fi

echo "[AGENT] K3s agent installed"
