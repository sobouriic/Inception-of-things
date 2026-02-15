#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

if ! kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
  echo "[P3] Argo CD CRDs not found. Running cluster bootstrap first..."
  bash "${SCRIPT_DIR}/cluster.sh"
fi

echo "[P3] Applying Argo CD Application..."
kubectl apply -f "${PROJECT_DIR}/confs/application.yaml"

echo "[P3] Forcing Argo CD refresh..."
kubectl annotate application development -n argocd argocd.argoproj.io/refresh=hard --overwrite

echo "[P3] Running verification checks..."
bash "${SCRIPT_DIR}/verify.sh"
