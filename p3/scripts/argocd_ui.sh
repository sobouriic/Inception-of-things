#!/usr/bin/env bash
set -euo pipefail

echo "=============================="
echo "[P3] Launching Argo CD UI"
echo "=============================="

if ! kubectl get ns argocd >/dev/null 2>&1; then
  echo "[ERROR] argocd namespace not found. Run cluster setup first."
  exit 1
fi

# Check if argocd-server pod is running
if ! kubectl get pods -n argocd | grep -q argocd-server; then
  echo "[ERROR] Argo CD server not running."
  exit 1
fi

echo "[P3] Retrieving admin password..."
PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo
echo "----------------------------------"
echo "Argo CD UI: https://localhost:8080"
echo "Username: admin"
echo "Password: ${PASSWORD}"
echo "----------------------------------"
echo

echo "[P3] Starting port-forward..."
echo "[INFO] Press Ctrl+C to stop."

kubectl port-forward svc/argocd-server -n argocd 8080:443
