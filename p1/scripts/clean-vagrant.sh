#!/bin/bash
set -euo pipefail

MACHINES=("sobouricS" "sobouricSW")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
PROJECT_PREFIX="$(basename "${PROJECT_DIR}")"

echo "Cleaning Vagrant + libvirt state..."

if command -v vagrant &>/dev/null; then
  echo "Trying: vagrant destroy -f"
  (
    cd "${PROJECT_DIR}"
    vagrant destroy -f || true
  )
fi

if command -v virsh &>/dev/null; then
  URIS=("qemu:///system" "qemu:///session")

  for URI in "${URIS[@]}"; do
    mapfile -t DOMAINS < <(virsh -c "${URI}" list --all --name 2>/dev/null | sed '/^$/d')
    [ "${#DOMAINS[@]}" -eq 0 ] && continue

    echo "Checking libvirt URI: ${URI}"
    CANDIDATES=()

    for DOMAIN in "${DOMAINS[@]}"; do
      if [[ "${DOMAIN}" == "${PROJECT_PREFIX}_"* ]]; then
        CANDIDATES+=("${DOMAIN}")
        continue
      fi
      for VM in "${MACHINES[@]}"; do
        if [[ "${DOMAIN}" == "${VM}" || "${DOMAIN}" =~ _${VM}$ ]]; then
          CANDIDATES+=("${DOMAIN}")
          break
        fi
      done
    done

    if [ "${#CANDIDATES[@]}" -eq 0 ]; then
      echo "No matching domains found in ${URI}"
      continue
    fi

    mapfile -t CANDIDATES < <(printf "%s\n" "${CANDIDATES[@]}" | sort -u)
    for DOMAIN in "${CANDIDATES[@]}"; do
      echo "Found libvirt domain: ${DOMAIN} (${URI})"

      echo "  Destroying ${DOMAIN} (if running)"
      virsh -c "${URI}" destroy "${DOMAIN}" || true

      echo "  Undefining ${DOMAIN} and removing storage"
      virsh -c "${URI}" undefine "${DOMAIN}" --remove-all-storage || true
    done
  done
fi

echo "Removing .vagrant directory"
rm -rf "${PROJECT_DIR}/.vagrant"

echo "Cleanup complete."
echo "You can now safely run: vagrant up --provider=libvirt"
