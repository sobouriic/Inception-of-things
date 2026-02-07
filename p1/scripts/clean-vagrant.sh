#!/bin/bash
set -e

MACHINES=("sobouricS" "sobouricSW")

echo " Cleaning Vagrant + libvirt state..."

if command -v vagrant &>/dev/null; then
  echo "▶ Trying: vagrant destroy -f"
  vagrant destroy -f || true
fi

if command -v virsh &>/dev/null; then
  for VM in "${MACHINES[@]}"; do
    if virsh dominfo "$VM" &>/dev/null; then
      echo "⚠ Found libvirt domain: $VM"

      echo "  🔻 Destroying $VM (if running)"
      virsh destroy "$VM" || true

      echo "  ❌ Undefining $VM and removing storage"
      virsh undefine "$VM" --remove-all-storage || true
    else
      echo "✔ $VM not found in libvirt"
    fi
  done
fi

echo "🗑 Removing .vagrant directory"
rm -rf .vagrant

echo "✅ Cleanup complete."
echo "👉 You can now safely run: vagrant up"
