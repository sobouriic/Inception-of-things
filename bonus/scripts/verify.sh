#!/usr/bin/env bash
set -euo pipefail

echo "=============================="
echo "[BONUS] VERIFICATION"
echo "=============================="

echo "[BONUS] Namespaces:"
kubectl get ns | grep -E "argocd|dev|gitlab" || true
echo

echo "[BONUS] GitLab pods:"
kubectl get pods -n gitlab
echo

echo "[BONUS] Argo CD application source:"
kubectl get application dev-app -n argocd -o jsonpath='{.spec.source.repoURL}'; echo
kubectl get application dev-app -n argocd -o wide
echo

echo "[BONUS] Dev resources:"
kubectl get pods -n dev
kubectl get svc -n dev
echo

echo "[BONUS] App response:"
curl -sS http://localhost:8888/ || true
echo
