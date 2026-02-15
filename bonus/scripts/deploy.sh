#!/usr/bin/env bash
set -euo pipefail

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
NC="\033[0m"

log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BONUS_DIR="$(dirname "${SCRIPT_DIR}")"
REPO_ROOT="$(dirname "${BONUS_DIR}")"
CONF_DIR="${BONUS_DIR}/confs"
GITLAB_PROJECT="sobouric"
GITLAB_USER="root"
GIT_USER_NAME="sobouric"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-sobouric@student.42.fr}"
MIN_FREE_GB="${MIN_FREE_GB:-12}"

create_namespace_if_missing() {
  local ns="$1"
  kubectl get namespace "${ns}" >/dev/null 2>&1 || kubectl create namespace "${ns}"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    log_error "Missing command: ${cmd}. Run: bash bonus/scripts/install.sh"
    exit 1
  fi
}

ensure_docker_access() {
  if ! docker info >/dev/null 2>&1; then
    log_error "Docker daemon is not reachable for current user."
    log_error "Run: sudo systemctl enable --now docker && sudo usermod -aG docker \$USER && newgrp docker"
    exit 1
  fi
}

check_free_disk_space() {
  local mount_target="/var/lib/docker"
  if [ ! -d "${mount_target}" ]; then
    mount_target="/"
  fi

  local free_kb
  free_kb="$(df -Pk "${mount_target}" | awk 'NR==2 {print $4}')"
  local min_kb=$((MIN_FREE_GB * 1024 * 1024))

  if [ "${free_kb}" -lt "${min_kb}" ]; then
    local free_gb
    free_gb="$(awk "BEGIN {printf \"%.1f\", ${free_kb}/1024/1024}")"
    log_error "Low free disk space on ${mount_target}: ${free_gb}GB available, require at least ${MIN_FREE_GB}GB."
    exit 1
  fi
}

stop_port_forward_if_running() {
  local pattern="$1"
  if pgrep -f "${pattern}" >/dev/null 2>&1; then
    log_warn "Stopping existing port-forward: ${pattern}"
    pkill -f "${pattern}" || true
    sleep 1
  fi
}

install_argocd_client() {
  if command -v argocd >/dev/null 2>&1; then
    log_info "Argo CD CLI already installed"
    return
  fi

  log_info "Installing Argo CD CLI..."
  curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
  chmod +x argocd
  sudo mv argocd /usr/local/bin/
  log_success "Argo CD CLI installed"
}

create_cluster_and_namespaces() {
  ensure_docker_access
  check_free_disk_space

  log_info "Pre-pulling k3d required images..."
  docker pull docker.io/rancher/k3s:v1.31.5-k3s1
  docker pull ghcr.io/k3d-io/k3d-tools:5.8.3

  if k3d cluster list | awk 'NR>1 {print $1}' | grep -qx "bonus"; then
    log_info "k3d cluster 'bonus' already exists"
  else
    log_info "Creating k3d cluster 'bonus'..."
    k3d cluster create bonus --port "8083:30080@loadbalancer" --timeout 300s
    log_success "k3d cluster created"
  fi

  log_info "Ensuring namespaces: argocd, dev, gitlab"
  create_namespace_if_missing argocd
  create_namespace_if_missing dev
  create_namespace_if_missing gitlab
  log_success "Namespaces ready"
}

install_argocd() {
  log_info "Installing Argo CD in namespace 'argocd'..."
  kubectl apply --server-side --force-conflicts -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  log_info "Waiting for Argo CD server..."
  kubectl wait deployment/argocd-server -n argocd --for=condition=Available --timeout=600s
  log_success "Argo CD installed"
}

deploy_gitlab() {
  check_free_disk_space

  local host_entry="127.0.0.1 gitlab.k3d.gitlab.com"
  if grep -q "${host_entry}" /etc/hosts; then
    log_info "Hosts entry already exists"
  else
    log_info "Adding hosts entry for GitLab"
    echo "${host_entry}" | sudo tee -a /etc/hosts >/dev/null
  fi

  helm repo add gitlab https://charts.gitlab.io/ >/dev/null 2>&1 || true
  helm repo update

  log_info "Installing GitLab Helm chart..."
  helm upgrade --install gitlab gitlab/gitlab \
    -n gitlab \
    -f https://gitlab.com/gitlab-org/charts/gitlab/raw/master/examples/values-minikube-minimum.yaml \
    --set global.hosts.domain=k3d.gitlab.com \
    --set global.hosts.externalIP=0.0.0.0 \
    --set global.hosts.https=false \
    --set global.edition=ce \
    --timeout 1200s
  log_success "GitLab chart installed"

  log_info "Waiting for GitLab webservice pod readiness (max 20m)..."
  local deadline=$((SECONDS + 1200))
  while true; do
    if kubectl get pods -n gitlab -l app=webservice 2>/dev/null | grep -q "Running"; then
      if kubectl get pods -n gitlab -l app=webservice 2>/dev/null | awk 'NR>1 {print $2}' | grep -q "^2/2$"; then
        break
      fi
    fi

    if [ "${SECONDS}" -ge "${deadline}" ]; then
      log_error "Timed out waiting for GitLab webservice readiness."
      kubectl get pods -n gitlab
      kubectl get events -n gitlab --sort-by=.lastTimestamp | tail -n 30
      exit 1
    fi

    kubectl get pods -n gitlab -l app=webservice --no-headers 2>/dev/null || true
    sleep 15
  done

  GITLAB_PASS=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath="{.data.password}" | base64 --decode)
  log_success "GitLab root password retrieved"

  log_info "Starting background port-forward for GitLab UI/API (localhost:8083)..."
  stop_port_forward_if_running "kubectl port-forward -n gitlab svc/gitlab-webservice-default 8083:8181"
  kubectl port-forward -n gitlab svc/gitlab-webservice-default 8083:8181 >/tmp/gitlab-pf.log 2>&1 &
  sleep 5
}

generate_gitlab_pat() {
  log_info "Generating GitLab PAT from toolbox pod..."

  local toolbox
  toolbox="$(kubectl get pods -n gitlab -l app=toolbox -o jsonpath='{.items[0].metadata.name}')"
  kubectl exec -n gitlab "${toolbox}" -- bash -lc "gitlab-rails runner 'u=User.find_by(username: \"root\"); u.personal_access_tokens.where(name: \"bonus-token\").destroy_all; t=u.personal_access_tokens.create!(name: \"bonus-token\", scopes: [:api], expires_at: 365.days.from_now.to_date); puts t.token'" >/tmp/gitlab_pat.txt

  PAT="$(tail -n1 /tmp/gitlab_pat.txt | tr -d '\r\n')"
  if [ -z "${PAT}" ]; then
    log_error "Failed to create GitLab PAT"
    exit 1
  fi
  log_success "GitLab PAT ready"
}

ensure_gitlab_project() {
  log_info "Ensuring GitLab project '${GITLAB_PROJECT}' exists..."

  local check_url="http://localhost:8083/api/v4/projects/${GITLAB_USER}%2F${GITLAB_PROJECT}"
  local create_url="http://localhost:8083/api/v4/projects"

  if curl -sf -H "PRIVATE-TOKEN: ${PAT}" "${check_url}" >/dev/null; then
    log_info "Project already exists"
  else
    curl -sS -X POST \
      -H "PRIVATE-TOKEN: ${PAT}" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"${GITLAB_PROJECT}\",\"path\":\"${GITLAB_PROJECT}\",\"visibility\":\"public\"}" \
      "${create_url}" >/dev/null
    log_success "Project created"
  fi
}

push_manifests_to_gitlab() {
  local workdir="/tmp/${GITLAB_PROJECT}-repo"
  rm -rf "${workdir}"
  mkdir -p "${workdir}"

  cp "${REPO_ROOT}/p3/confs/deployment.yaml" "${workdir}/"
  cp "${REPO_ROOT}/p3/confs/service.yaml" "${workdir}/"

  git config --global user.email "${GIT_USER_EMAIL}"
  git config --global user.name "${GIT_USER_NAME}"

  pushd "${workdir}" >/dev/null
  git init
  git checkout -B main
  git add .
  if git diff --cached --quiet; then
    log_info "No manifest changes to commit"
  else
    git commit -m "initial manifests"
  fi
  git remote remove origin >/dev/null 2>&1 || true
  git remote add origin "http://oauth2:${PAT}@localhost:8083/${GITLAB_USER}/${GITLAB_PROJECT}.git"
  git push -u origin main
  popd >/dev/null

  log_success "Manifests pushed to local GitLab"
}

configure_argocd_and_deploy_app() {
  log_info "Starting port-forward for Argo CD API (localhost:8080)..."
  stop_port_forward_if_running "kubectl port-forward -n argocd svc/argocd-server 8080:443"
  kubectl port-forward svc/argocd-server -n argocd 8080:443 >/tmp/argocd-pf.log 2>&1 &
  sleep 5

  local admin_pw
  admin_pw=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

  argocd login localhost:8080 --insecure --username admin --password "${admin_pw}"
  log_success "Logged into Argo CD"

  log_info "Applying Argo CD config and application manifests..."
  kubectl apply -f "${CONF_DIR}/argo-cd.yaml" -n argocd
  kubectl apply -f "${CONF_DIR}/application.yaml" -n argocd
  kubectl annotate application development -n argocd argocd.argoproj.io/refresh=hard --overwrite
  log_success "Argo CD application applied"
}

wait_and_portforward_app() {
  log_info "Waiting for service 'wil-playground' in namespace 'dev'..."
  until kubectl get svc wil-playground -n dev >/dev/null 2>&1; do
    log_warn "Service not created yet, waiting..."
    sleep 5
  done

  log_info "Port-forwarding app to localhost:8888 (Ctrl+C to stop)..."
  kubectl port-forward svc/wil-playground -n dev 8888:8888
}

main() {
  log_info "=== Bonus step 2/2: Deploying cluster, GitLab and app ==="

  require_cmd docker
  require_cmd k3d
  require_cmd kubectl
  require_cmd helm
  require_cmd git

  create_cluster_and_namespaces
  install_argocd
  install_argocd_client
  deploy_gitlab
  generate_gitlab_pat
  ensure_gitlab_project
  push_manifests_to_gitlab
  configure_argocd_and_deploy_app
  wait_and_portforward_app
}

main
