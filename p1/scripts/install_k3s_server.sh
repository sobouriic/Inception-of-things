#!/bin/bash
set -e

K3S_SHARED_TOKEN="inception-iot-token"

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

echo "[SERVER] Installing K3s server..."
curl -sfL https://get.k3s.io | \
  K3S_TOKEN="${K3S_SHARED_TOKEN}" \
  INSTALL_K3S_EXEC="server --node-ip=192.168.56.110 --advertise-address=192.168.56.110 --tls-san=192.168.56.110" \
  sh -

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

echo "[SERVER] K3s server ready"
