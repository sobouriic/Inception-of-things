#!/usr/bin/env bash
set -euo pipefail

echo "=============================="
echo "[P3] VERIFICATION"
echo "=============================="

echo "[P3] Namespaces:"
kubectl get ns | grep -E "argocd|dev" || true
echo

echo "[P3] Argo CD pods:"
kubectl get pods -n argocd
echo

echo "[P3] Argo CD Applications:"
kubectl get applications -n argocd -o wide
echo

echo "[P3] Dev resources:"
kubectl get pods -n dev
kubectl get svc -n dev
echo

echo "[P3] App response:"
curl -sS http://localhost:8888/ || true
echo
