#!/bin/bash
set -e

TOKEN_FILE="/vagrant/confs/k3s_token"
SERVER_IP="192.168.56.110"

mkdir -p "$(dirname "${TOKEN_FILE}")"

echo "[SERVER] Preparing system packages..."
dnf makecache
dnf install -y curl iproute net-tools

systemctl disable --now firewalld >/dev/null 2>&1 || true

if [ -n "${K3S_SHARED_TOKEN:-}" ]; then
  echo "[SERVER] Using K3S_SHARED_TOKEN from environment."
elif [ -f "${TOKEN_FILE}" ]; then
  K3S_SHARED_TOKEN="$(cat "${TOKEN_FILE}")"
  echo "[SERVER] Using existing token from ${TOKEN_FILE}."
else
  echo "[SERVER] Generating fallback K3s token..."
  K3S_SHARED_TOKEN="$(openssl rand -hex 32)"
  umask 077
  echo "${K3S_SHARED_TOKEN}" > "${TOKEN_FILE}"
  chmod 600 "${TOKEN_FILE}"
  umask 022
fi

echo "[SERVER] Installing K3s server..."
curl -sfL https://get.k3s.io | \
  K3S_TOKEN="${K3S_SHARED_TOKEN}" \
  INSTALL_K3S_EXEC="server --node-ip=${SERVER_IP} --advertise-address=${SERVER_IP} --tls-san=${SERVER_IP} --write-kubeconfig-mode=644 --disable traefik --disable metrics-server --disable servicelb" \
  sh -

if [ -f /var/lib/rancher/k3s/server/node-token ]; then
  umask 077
  cp /var/lib/rancher/k3s/server/node-token "${TOKEN_FILE}"
  chmod 600 "${TOKEN_FILE}"
  umask 022
  echo "[SERVER] Wrote node-token to ${TOKEN_FILE}."
else
  echo "[SERVER] WARNING: node-token not found; token file not updated."
fi

echo "[SERVER] Waiting for kubeconfig..."
for _ in $(seq 1 60); do
  if [ -f /etc/rancher/k3s/k3s.yaml ]; then
    break
  fi
  sleep 2
done

echo "[SERVER] Writing server IP (${SERVER_IP}) to /vagrant/server_ip"
echo "${SERVER_IP}" > /vagrant/server_ip
chmod 644 /vagrant/server_ip

# K3s typically provides kubectl via /usr/local/bin/k3s.
if [ -x /usr/local/bin/k3s ] && [ ! -e /usr/local/bin/kubectl ]; then
  ln -s /usr/local/bin/k3s /usr/local/bin/kubectl
fi

if ! PATH="/usr/local/bin:${PATH}" command -v kubectl >/dev/null 2>&1; then
  echo "[SERVER] Installing kubectl (fallback)..."
  KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  TMP_KUBECTL="$(mktemp /tmp/kubectl.XXXXXX)"
  curl -fsSL -o "${TMP_KUBECTL}" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  install -m 0755 "${TMP_KUBECTL}" /usr/local/bin/kubectl
  rm -f "${TMP_KUBECTL}"
fi

echo "[SERVER] Configuring kubectl for vagrant user..."
if id vagrant >/dev/null 2>&1; then
  install -d -m 700 -o vagrant -g vagrant /home/vagrant/.kube
  if [ -f /etc/rancher/k3s/k3s.yaml ]; then
    cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
    chown vagrant:vagrant /home/vagrant/.kube/config
  else
    echo "[SERVER] WARNING: kubeconfig not found yet; skipping /home/vagrant/.kube/config copy."
  fi
  if ! grep -q "alias k=" /home/vagrant/.bashrc 2>/dev/null; then
    echo "alias k=/usr/local/bin/kubectl" >> /home/vagrant/.bashrc
  fi
fi

echo "[SERVER] K3s server ready"
