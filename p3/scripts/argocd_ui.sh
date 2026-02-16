#!/usr/bin/env bash
set -euo pipefail

PORT="${ARGOCD_UI_PORT:-8080}"

echo "=============================="
echo "[P3] Launching Argo CD UI"
echo "=============================="

if ! kubectl get ns argocd >/dev/null 2>&1; then
  echo "[ERROR] argocd namespace not found. Run cluster setup first."
  exit 1
fi

if ! kubectl get pods -n argocd | grep -q argocd-server; then
  echo "[ERROR] Argo CD server not running."
  exit 1
fi

echo "[P3] Retrieving admin password..."
PASSWORD="(initial secret not available; use your current admin password)"
if kubectl -n argocd get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  PASSWORD="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
fi

echo
echo "----------------------------------"
echo "Argo CD UI: http://localhost:${PORT}"
echo "Username: admin"
echo "Password: ${PASSWORD}"
echo "----------------------------------"
echo

echo "[P3] Starting port-forward..."
echo "[INFO] Press Ctrl+C to stop."

pkill -f "kubectl port-forward .*argocd-server .*${PORT}:" >/dev/null 2>&1 || true
sleep 1

# Use HTTP service port (80) to avoid TLS/backend cert edge-cases seen with 443.
if ! kubectl port-forward svc/argocd-server -n argocd "${PORT}:80"; then
  echo "[WARN] Service port-forward failed, retrying via deployment..."
  kubectl rollout restart deployment/argocd-server -n argocd >/dev/null 2>&1 || true
  kubectl rollout status deployment/argocd-server -n argocd --timeout=180s >/dev/null 2>&1 || true
  kubectl port-forward deployment/argocd-server -n argocd "${PORT}:8080"
fi
