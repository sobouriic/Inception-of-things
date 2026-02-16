#!/usr/bin/env bash
set -euo pipefail

echo "=============================="
echo "[BONUS] VERIFICATION"
echo "=============================="

echo "[BONUS] Namespaces:"
kubectl get ns | grep -E "argocd|dev|gitlab" || true
echo

echo "[BONUS] Argo CD application:"
kubectl get application development -n argocd || true
echo

echo "[BONUS] GitLab pods:"
kubectl get pods -n gitlab || true
echo

echo "[BONUS] Dev pods:"
kubectl get pods -n dev || true
echo

echo "[BONUS] App response:"
curl -sS http://localhost:8888 || true
echo
