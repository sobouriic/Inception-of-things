#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[BONUS] ERROR: no reachable Kubernetes cluster."
  echo "[BONUS] Start your Part 3 cluster first:"
  echo "        bash p3/scripts/cluster.sh"
  exit 1
fi

echo "[BONUS] Creating gitlab namespace..."
kubectl apply -f "${PROJECT_DIR}/confs/gitlab-namespace.yaml"

echo "[BONUS] Adding/updating GitLab Helm repo..."
helm repo add gitlab https://charts.gitlab.io >/dev/null 2>&1 || true
helm repo update

echo "[BONUS] Installing GitLab (this can take several minutes)..."
helm upgrade --install gitlab gitlab/gitlab \
  --namespace gitlab \
  --set global.edition=ce \
  --set global.hosts.domain=127.0.0.1.nip.io \
  --set global.hosts.https=false \
  --set global.ingress.configureCertmanager=false \
  --set installCertmanager=false \
  --set gitlab-runner.install=false \
  --set prometheus.install=false

echo "[BONUS] Waiting for GitLab webservice rollout..."
kubectl rollout status deployment/gitlab-webservice-default -n gitlab --timeout=900s || true

echo "[BONUS] GitLab namespace status:"
kubectl get pods -n gitlab

echo "[BONUS] Initial root password:"
kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath="{.data.password}" | base64 -d || true
echo
echo "[BONUS] Open UI with port-forward if needed:"
echo "kubectl port-forward svc/gitlab-webservice-default -n gitlab 8081:8181"
