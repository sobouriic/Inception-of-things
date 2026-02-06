#!/bin/bash
set -e

TOKEN_FILE="/vagrant/confs/k3s_token"

if [ -f /etc/centos-release ] && grep -q "CentOS Linux release 7" /etc/centos-release; then
  echo "[SERVER] Fixing CentOS 7 repositories..."
  sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-Base.repo
  sed -i 's|^#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-Base.repo
fi

echo "[SERVER] Preparing system packages..."
if command -v dnf >/dev/null 2>&1; then
  dnf makecache
  dnf install -y curl iproute net-tools firewalld
else
  yum clean all
  yum makecache
  yum install -y curl iproute net-tools firewalld
fi

systemctl disable --now firewalld >/dev/null 2>&1 || true

if [ -n "${K3S_SHARED_TOKEN:-}" ]; then
  echo "[SERVER] Using K3S_SHARED_TOKEN from environment."
elif [ -f "${TOKEN_FILE}" ]; then
  K3S_SHARED_TOKEN="$(cat "${TOKEN_FILE}")"
  echo "[SERVER] Using existing token from ${TOKEN_FILE}."
else
  echo "[SERVER] Generating secure K3s token..."
  if command -v openssl >/dev/null 2>&1; then
    K3S_SHARED_TOKEN="$(openssl rand -hex 32)"
  else
    K3S_SHARED_TOKEN="$(head -c 32 /dev/urandom | hexdump -v -e '/1 "%02x"')"
  fi
  umask 077
  echo "${K3S_SHARED_TOKEN}" > "${TOKEN_FILE}"
  chmod 600 "${TOKEN_FILE}"
  umask 022
fi

echo "[SERVER] Installing K3s server..."
curl -sfL https://get.k3s.io | \
  K3S_TOKEN="${K3S_SHARED_TOKEN}" \
  INSTALL_K3S_EXEC="server --node-ip=192.168.56.110 --advertise-address=192.168.56.110 --tls-san=192.168.56.110" \
  sh -

# Ensure the token file exists for the agent, even if /vagrant was not ready earlier.
if [ ! -f "${TOKEN_FILE}" ]; then
  if [ -n "${K3S_SHARED_TOKEN:-}" ]; then
    umask 077
    echo "${K3S_SHARED_TOKEN}" > "${TOKEN_FILE}"
    chmod 600 "${TOKEN_FILE}"
    umask 022
    echo "[SERVER] Wrote token to ${TOKEN_FILE}."
  elif [ -f /var/lib/rancher/k3s/server/node-token ]; then
    umask 077
    cp /var/lib/rancher/k3s/server/node-token "${TOKEN_FILE}"
    chmod 600 "${TOKEN_FILE}"
    umask 022
    echo "[SERVER] Wrote node-token to ${TOKEN_FILE}."
  fi
fi

SERVER_IP="$(ip -4 -o addr show scope global | awk '/192\\.168\\.56\\./ {split($4,a,"/"); print a[1]; found=1; exit} END {if (!found) {split($4,a,"/"); print a[1]}}')"
echo "[SERVER] Writing server IP (${SERVER_IP}) to /vagrant/server_ip"
echo "${SERVER_IP}" > /vagrant/server_ip
chmod 644 /vagrant/server_ip

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[SERVER] Installing kubectl..."
  KUBECTL_VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
  curl -L -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x /usr/local/bin/kubectl
fi

echo "[SERVER] Configuring kubectl for vagrant user..."
if id vagrant >/dev/null 2>&1; then
  install -d -m 700 -o vagrant -g vagrant /home/vagrant/.kube
  cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
  chown vagrant:vagrant /home/vagrant/.kube/config
  if ! grep -q "alias k=" /home/vagrant/.bashrc 2>/dev/null; then
    echo "alias k=/usr/local/bin/kubectl" >> /home/vagrant/.bashrc
  fi
fi

echo "[SERVER] K3s server ready"
