#!/bin/bash
set -e

echo "[SERVER] Fixing CentOS 7 repositories..."

sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-Base.repo
sed -i 's|^#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-Base.repo

yum clean all
yum makecache

echo "[SERVER] Installing K3s server..."
curl -sfL https://get.k3s.io | sh -

echo "[SERVER] Waiting for token..."
while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
  sleep 1
done

echo "[SERVER] Copying token to /vagrant/token"
cp /var/lib/rancher/k3s/server/node-token /vagrant/token
chmod 644 /vagrant/token

echo "[SERVER] K3s server ready"
