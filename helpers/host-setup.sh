#!/bin/bash
set -e

echo "🔍 Detecting host environment..."

OS_ID=$(grep "^ID=" /etc/os-release | cut -d= -f2 | tr -d '"')
OS_VERSION=$(grep "^VERSION_CODENAME=" /etc/os-release | cut -d= -f2 | tr -d '"')

echo "➡ OS: $OS_ID ($OS_VERSION)"

echo
echo "🔧 Checking Vagrant..."
if ! command -v vagrant >/dev/null 2>&1; then
  echo "❌ Vagrant not installed"
  exit 1
fi
echo "✅ Vagrant found"

echo
echo "🔍 Checking VirtualBox..."
if command -v VBoxManage >/dev/null 2>&1; then
  echo "✅ VirtualBox detected"
  echo
  echo "👉 Use this command:"
  echo "vagrant up --provider=virtualbox"
  exit 0
fi

echo "❌ VirtualBox not available"

echo
echo "🔍 Checking libvirt..."
if systemctl list-unit-files | grep -q libvirtd \
  && command -v virsh >/dev/null 2>&1 \
  && command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "✅ libvirt + qemu detected"
else
  echo "📦 Installing libvirt stack..."
  sudo apt update
  sudo apt install -y qemu-system-x86 qemu-kvm libvirt-daemon-system libvirt-clients virt-manager
fi

echo
echo "🚀 Enabling libvirt..."
sudo systemctl enable libvirtd
sudo systemctl start libvirtd

echo
echo "🌐 Ensuring libvirt default network is active..."
if sudo virsh net-info default >/dev/null 2>&1; then
  sudo virsh net-start default >/dev/null 2>&1 || true
  sudo virsh net-autostart default
  echo "✅ libvirt default network ready"
else
  echo "⚠️ libvirt network 'default' not found; create it if Vagrant cannot get VM IP"
fi

echo
echo "👤 Adding user to libvirt & kvm groups..."
sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER

echo
echo "📦 Installing vagrant-libvirt plugin..."
vagrant plugin install vagrant-libvirt || true

echo
echo "⚠️ IMPORTANT:"
echo "You MUST logout/login (or reboot) now."
echo
echo "👉 After logging back in, run:"
echo "cd p1 && vagrant up"
