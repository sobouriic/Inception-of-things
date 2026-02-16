#!/usr/bin/env bash
set -euo pipefail

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
NC="\033[0m"

log_info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }

safe_kubectl_delete() {
  if command -v kubectl >/dev/null 2>&1; then
    kubectl "$@" --ignore-not-found >/dev/null 2>&1 || true
  fi
}

safe_helm_uninstall() {
  if command -v helm >/dev/null 2>&1; then
    helm uninstall gitlab -n gitlab >/dev/null 2>&1 || true
  fi
}

kill_pf() {
  local pattern="$1"
  if pgrep -f "${pattern}" >/dev/null 2>&1; then
    pkill -f "${pattern}" || true
  fi
}

main() {
  log_info "Cleaning bonus resources (cluster + namespaces + local temp files)..."

  kill_pf "kubectl port-forward -n gitlab svc/gitlab-webservice-default 8083:8181"
  kill_pf "kubectl port-forward -n argocd svc/argocd-server 8080:443"
  kill_pf "kubectl port-forward svc/wil-playground -n dev 8888:8888"

  safe_helm_uninstall

  safe_kubectl_delete delete application development -n argocd
  safe_kubectl_delete delete -f bonus/confs/argo-cd.yaml -n argocd
  safe_kubectl_delete delete namespace gitlab
  safe_kubectl_delete delete namespace argocd
  safe_kubectl_delete delete namespace dev

  if command -v k3d >/dev/null 2>&1; then
    k3d cluster delete bonus >/dev/null 2>&1 || true
  else
    log_warn "k3d not found, skipping cluster deletion"
  fi

  rm -f /tmp/gitlab_pat.txt /tmp/gitlab-pf.log /tmp/argocd-pf.log
  rm -rf /tmp/sobouric-repo

  if grep -q "127.0.0.1 gitlab.k3d.gitlab.com" /etc/hosts 2>/dev/null; then
    sudo sed -i '/127.0.0.1 gitlab.k3d.gitlab.com/d' /etc/hosts || true
  fi

  log_ok "Bonus cleanup completed"
}

main
