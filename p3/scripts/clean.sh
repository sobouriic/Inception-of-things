#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="iot-cluster"

echo "=============================="
echo "[P3 CLEAN] Starting full cleanup"
echo "=============================="

# Check if cluster exists
if k3d cluster list | grep -q "^${CLUSTER_NAME}\b"; then
    echo "[P3 CLEAN] Cluster ${CLUSTER_NAME} exists."

    echo "[P3 CLEAN] Deleting Argo CD Application (if exists)..."
    kubectl delete application dev-app -n argocd --ignore-not-found=true || true

    echo "[P3 CLEAN] Deleting namespaces..."
    kubectl delete namespace dev --ignore-not-found=true || true
    kubectl delete namespace argocd --ignore-not-found=true || true

    echo "[P3 CLEAN] Deleting K3d cluster..."
    k3d cluster delete "${CLUSTER_NAME}"

else
    echo "[P3 CLEAN] Cluster ${CLUSTER_NAME} does not exist. Skipping cluster deletion."
fi

echo "[P3 CLEAN] Cleaning Docker unused resources..."
docker system prune -af || true

echo "=============================="
echo "[P3 CLEAN] Cleanup complete."
echo "=============================="
