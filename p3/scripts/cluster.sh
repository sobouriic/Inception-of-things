#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="iot-cluster"
HOST_PORT="${HOST_PORT:-8888}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

port_is_listening() {
  local port="$1"
  ss -ltn "sport = :${port}" 2>/dev/null | tail -n +2 | grep -q .
}

stop_stale_port_forward() {
  local port="$1"
  local pattern="kubectl port-forward svc/wil-playground -n dev ${port}:8888"

  if pgrep -f "${pattern}" >/dev/null 2>&1; then
    echo "[P3] Stopping stale port-forward on ${port}..."
    pkill -f "${pattern}" || true
    sleep 1
  fi
}

ensure_host_port_available() {
  local port="$1"

  stop_stale_port_forward "${port}"
  if port_is_listening "${port}"; then
    echo "[P3] ERROR: Host port ${port} is already in use."
    echo "[P3] Free it, or run with another port:"
    echo "[P3] HOST_PORT=18888 ./cluster.sh"
    exit 1
  fi
}

ensure_kube_context() {
  local context="k3d-${CLUSTER_NAME}"

  echo "[P3] Ensuring kubeconfig context: ${context}"
  k3d kubeconfig merge "${CLUSTER_NAME}" --kubeconfig-switch-context >/dev/null 2>&1 || \
    k3d kubeconfig merge "${CLUSTER_NAME}" >/dev/null 2>&1 || true

  if kubectl config get-contexts "${context}" >/dev/null 2>&1; then
    kubectl config use-context "${context}" >/dev/null
  fi

  local tries=0
  until kubectl cluster-info >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "${tries}" -ge 20 ]; then
      echo "[P3] ERROR: Cannot reach Kubernetes API for context ${context}."
      echo "[P3] Check with: kubectl config current-context && kubectl cluster-info"
      exit 1
    fi
    sleep 1
  done
}

echo "[P3] Creating cluster..."
if k3d cluster list | awk '{print $1}' | grep -qx "${CLUSTER_NAME}"; then
  echo "[P3] Cluster ${CLUSTER_NAME} already exists, skipping create."
else
  ensure_host_port_available "${HOST_PORT}"
  k3d cluster create "${CLUSTER_NAME}" --servers 1 --agents 1 --port "${HOST_PORT}:30080@loadbalancer"
fi

ensure_kube_context

echo "[P3] Creating namespaces..."
kubectl apply -f "${PROJECT_DIR}/confs/namespace.yaml"

echo "[P3] Installing Argo CD..."
kubectl apply --server-side --force-conflicts -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

echo "[P3] Applying Argo CD Application..."
kubectl apply -f "${PROJECT_DIR}/confs/application.yaml"

echo "[P3] Setup complete."
echo "[P3] App URL: http://localhost:${HOST_PORT}"
echo "[P3] Argo CD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "[P3] Argo CD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
