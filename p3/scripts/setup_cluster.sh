#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="iot-cluster"

echo "[P3] Creating cluster..."
if k3d cluster list | awk '{print $1}' | grep -qx "${CLUSTER_NAME}"; then
  echo "[P3] Cluster ${CLUSTER_NAME} already exists, skipping create."
else
  k3d cluster create "${CLUSTER_NAME}" --servers 1 --agents 1 --port "8888:30080@loadbalancer"
fi

echo "[P3] Creating namespaces..."
kubectl apply -f confs/namespace.yaml

echo "[P3] Installing Argo CD..."
kubectl apply --server-side --force-conflicts -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

echo "[P3] Applying Argo CD Application..."
kubectl apply -f confs/application.yaml

echo "[P3] Setup complete."
echo "[P3] Argo CD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "[P3] Argo CD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
