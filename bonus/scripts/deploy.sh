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
GITLAB_VALUES_FILE="${GITLAB_VALUES_FILE:-${CONF_DIR}/gitlab-values-light.yaml}"
GITLAB_LOCAL_PORT="${GITLAB_LOCAL_PORT:-8083}"
ARGOCD_LOCAL_PORT="${ARGOCD_LOCAL_PORT:-8080}"
FORCE_ARGOCD_APPLY="${FORCE_ARGOCD_APPLY:-false}"
FORCE_GITLAB_UPGRADE="${FORCE_GITLAB_UPGRADE:-false}"
GITLAB_PROJECT="sobouric"
GITLAB_USER="root"
GIT_USER_NAME="sobouric"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-socarlett03@gmail.com}"
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

free_local_port_if_busy() {
  local port="$1"
  local pids

  pids="$(ss -ltnp "sport = :${port}" 2>/dev/null | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | sort -u)"
  if [ -n "${pids}" ]; then
    log_warn "Port ${port} is busy, stopping stale local listeners (PID: ${pids})"
    # shellcheck disable=SC2086
    kill ${pids} >/dev/null 2>&1 || true
    sleep 1
  fi
}

start_gitlab_port_forward() {
  local candidates=("${GITLAB_LOCAL_PORT}" 18083 28083)
  local port

  for port in "${candidates[@]}"; do
    stop_port_forward_if_running "kubectl port-forward -n gitlab svc/gitlab-webservice-default ${port}:8181"
    free_local_port_if_busy "${port}"
    kubectl port-forward -n gitlab svc/gitlab-webservice-default "${port}:8181" >/tmp/gitlab-pf.log 2>&1 &
    sleep 3

    if pgrep -f "kubectl port-forward -n gitlab svc/gitlab-webservice-default ${port}:8181" >/dev/null 2>&1; then
      GITLAB_LOCAL_PORT="${port}"
      log_info "GitLab port-forward active on localhost:${GITLAB_LOCAL_PORT}"
      return 0
    fi
  done

  log_error "Could not start GitLab port-forward on fallback ports."
  tail -n 40 /tmp/gitlab-pf.log 2>/dev/null || true
  exit 1
}

start_argocd_port_forward() {
  local candidates=("${ARGOCD_LOCAL_PORT}" 18080 28080)
  local port

  for port in "${candidates[@]}"; do
    stop_port_forward_if_running "kubectl port-forward -n argocd svc/argocd-server ${port}:443"
    free_local_port_if_busy "${port}"
    kubectl port-forward svc/argocd-server -n argocd "${port}:443" >/tmp/argocd-pf.log 2>&1 &
    sleep 3

    if pgrep -f "kubectl port-forward svc/argocd-server -n argocd ${port}:443" >/dev/null 2>&1; then
      ARGOCD_LOCAL_PORT="${port}"
      log_info "Argo CD port-forward active on localhost:${ARGOCD_LOCAL_PORT}"
      return 0
    fi
  done

  log_error "Could not start Argo CD port-forward on fallback ports."
  tail -n 40 /tmp/argocd-pf.log 2>/dev/null || true
  exit 1
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
  if [ "${FORCE_ARGOCD_APPLY}" != "true" ] && kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
    if kubectl wait deployment/argocd-server -n argocd --for=condition=Available --timeout=60s >/dev/null 2>&1; then
      log_info "Argo CD already installed, skipping re-apply"
      return
    fi
  fi

  log_info "Installing Argo CD in namespace 'argocd'..."
  kubectl apply --server-side --force-conflicts -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  log_info "Waiting for Argo CD server..."
  kubectl wait deployment/argocd-server -n argocd --for=condition=Available --timeout=600s
  log_success "Argo CD installed"
}

deploy_gitlab() {
  check_free_disk_space

  if [ ! -f "${GITLAB_VALUES_FILE}" ]; then
    log_error "Missing GitLab values file: ${GITLAB_VALUES_FILE}"
    log_error "Expected default: bonus/confs/gitlab-values-light.yaml"
    exit 1
  fi

  local host_entry="127.0.0.1 gitlab.k3d.gitlab.com"
  if grep -q "${host_entry}" /etc/hosts; then
    log_info "Hosts entry already exists"
  else
    log_info "Adding hosts entry for GitLab"
    echo "${host_entry}" | sudo tee -a /etc/hosts >/dev/null
  fi

  if [ "${FORCE_GITLAB_UPGRADE}" = "true" ] || ! helm status gitlab -n gitlab >/dev/null 2>&1; then
    helm repo add gitlab https://charts.gitlab.io/ >/dev/null 2>&1 || true
    helm repo update

    prepare_gitlab_resources_for_upgrade

    log_info "Installing lightweight GitLab Helm chart profile..."
    helm upgrade --install gitlab gitlab/gitlab \
      -n gitlab \
      -f "${GITLAB_VALUES_FILE}" \
      --timeout 1200s
    log_success "GitLab chart installed"
  else
    log_info "GitLab release already installed, skipping Helm upgrade"
  fi

  optimize_gitlab_for_low_memory

  log_info "Waiting for GitLab webservice pod readiness (max 20m)..."
  local deadline=$((SECONDS + 1200))
  local dns_recoveries=0
  local memory_recoveries=0
  while true; do
    if kubectl get pods -n gitlab -l app=webservice --no-headers 2>/dev/null | grep -q "Running"; then
      if kubectl get pods -n gitlab -l app=webservice --no-headers 2>/dev/null | awk '{print $2}' | grep -Eq "1/1|2/2|3/3"; then
        break
      fi
    fi

    if webservice_has_dns_pull_issue; then
      if [ "${dns_recoveries}" -lt 2 ]; then
        dns_recoveries=$((dns_recoveries + 1))
        recover_webservice_dns_pull
      fi
    fi

    if webservice_has_memory_scheduling_issue; then
      if [ "${memory_recoveries}" -lt 2 ]; then
        memory_recoveries=$((memory_recoveries + 1))
        recover_webservice_memory_pressure
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

  log_info "Starting background port-forward for GitLab UI/API..."
  start_gitlab_port_forward
  wait_for_gitlab_api
}

prepare_gitlab_resources_for_upgrade() {
  if ! kubectl get namespace gitlab >/dev/null 2>&1; then
    return
  fi

  log_info "Preparing existing GitLab deployments for Helm upgrade compatibility..."

  if kubectl get deploy gitlab-webservice-default -n gitlab >/dev/null 2>&1; then
    kubectl set resources deploy/gitlab-webservice-default -n gitlab --containers='*' \
      --requests=cpu=2500m,memory=2500Mi --limits=cpu=3000m,memory=3Gi >/dev/null 2>&1 || true
  fi

  if kubectl get deploy gitlab-sidekiq-all-in-1-v2 -n gitlab >/dev/null 2>&1; then
    kubectl set resources deploy/gitlab-sidekiq-all-in-1-v2 -n gitlab --containers='*' \
      --requests=cpu=1000m,memory=2Gi --limits=cpu=1500m,memory=3Gi >/dev/null 2>&1 || true
  fi
}

webservice_has_dns_pull_issue() {
  local pod
  pod="$(kubectl get pods -n gitlab -l app=webservice --no-headers 2>/dev/null | awk '$3 ~ /ErrImagePull|ImagePullBackOff/ {print $1; exit}')"
  if [ -z "${pod}" ]; then
    return 1
  fi

  if kubectl describe pod -n gitlab "${pod}" 2>/dev/null | grep -q "lookup registry.gitlab.com"; then
    return 0
  fi
  return 1
}

recover_webservice_dns_pull() {
  log_warn "Detected DNS image-pull failure for webservice. Restarting CoreDNS and retrying failed webservice pods..."

  kubectl -n kube-system rollout restart deployment/coredns >/dev/null 2>&1 || true
  kubectl -n kube-system rollout status deployment/coredns --timeout=180s >/dev/null 2>&1 || true

  local failed_pods
  failed_pods="$(kubectl get pods -n gitlab -l app=webservice --no-headers 2>/dev/null | awk '$3 ~ /ErrImagePull|ImagePullBackOff/ {print $1}')"
  if [ -n "${failed_pods}" ]; then
    # shellcheck disable=SC2086
    kubectl delete pod -n gitlab ${failed_pods} >/dev/null 2>&1 || true
  fi
}

webservice_has_memory_scheduling_issue() {
  local pod
  pod="$(kubectl get pods -n gitlab -l app=webservice --no-headers 2>/dev/null | awk '$3 == "Pending" {print $1; exit}')"
  if [ -z "${pod}" ]; then
    return 1
  fi

  if kubectl describe pod -n gitlab "${pod}" 2>/dev/null | grep -q "Insufficient memory"; then
    return 0
  fi
  return 1
}

recover_webservice_memory_pressure() {
  log_warn "Detected memory scheduling pressure. Re-applying low-memory GitLab tuning..."
  optimize_gitlab_for_low_memory
}

optimize_gitlab_for_low_memory() {
  log_info "Applying low-memory runtime tuning for GitLab..."

  local hpas=(
    gitlab-webservice-default
    gitlab-sidekiq-all-in-1-v2
    gitlab-kas
    gitlab-gitlab-shell
  )

  local deployments=(
    gitlab-webservice-default
    gitlab-sidekiq-all-in-1-v2
    gitlab-kas
    gitlab-gitlab-shell
  )

  local hpa
  for hpa in "${hpas[@]}"; do
    if kubectl get hpa "${hpa}" -n gitlab >/dev/null 2>&1; then
      kubectl delete hpa "${hpa}" -n gitlab >/dev/null 2>&1 || true
    fi
  done

  local dep
  for dep in "${deployments[@]}"; do
    if kubectl get deploy "${dep}" -n gitlab >/dev/null 2>&1; then
      kubectl scale deploy "${dep}" -n gitlab --replicas=1 >/dev/null 2>&1 || true
    fi
  done

  if kubectl get deploy gitlab-webservice-default -n gitlab >/dev/null 2>&1; then
    kubectl patch deploy gitlab-webservice-default -n gitlab --type merge -p \
      '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":0,"maxUnavailable":1}}}}' >/dev/null 2>&1 || true
    kubectl set resources deploy/gitlab-webservice-default -n gitlab --containers='*' \
      --requests=cpu=150m,memory=384Mi --limits=cpu=800m,memory=2Gi >/dev/null 2>&1 || true
  fi

  if kubectl get deploy gitlab-sidekiq-all-in-1-v2 -n gitlab >/dev/null 2>&1; then
    kubectl set resources deploy/gitlab-sidekiq-all-in-1-v2 -n gitlab --containers='*' \
      --requests=cpu=100m,memory=256Mi --limits=cpu=500m,memory=768Mi >/dev/null 2>&1 || true
  fi

  if kubectl get deploy gitlab-kas -n gitlab >/dev/null 2>&1; then
    kubectl set resources deploy/gitlab-kas -n gitlab --containers='*' \
      --requests=cpu=50m,memory=64Mi --limits=cpu=250m,memory=256Mi >/dev/null 2>&1 || true
  fi

  if kubectl get deploy gitlab-gitlab-shell -n gitlab >/dev/null 2>&1; then
    kubectl set resources deploy/gitlab-gitlab-shell -n gitlab --containers='*' \
      --requests=cpu=50m,memory=64Mi --limits=cpu=250m,memory=256Mi >/dev/null 2>&1 || true
  fi
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
  wait_for_gitlab_api

  local check_url="http://localhost:${GITLAB_LOCAL_PORT}/api/v4/projects/${GITLAB_USER}%2F${GITLAB_PROJECT}"
  local create_url="http://localhost:${GITLAB_LOCAL_PORT}/api/v4/projects"

  if gitlab_api_retry GET "${check_url}" >/dev/null; then
    log_info "Project already exists"
  else
    gitlab_api_retry POST "${create_url}" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"${GITLAB_PROJECT}\",\"path\":\"${GITLAB_PROJECT}\",\"visibility\":\"public\"}" >/dev/null
    log_success "Project created"
  fi
}

wait_for_gitlab_api() {
  log_info "Waiting for GitLab API readiness on localhost:${GITLAB_LOCAL_PORT}..."
  local deadline=$((SECONDS + 300))
  while true; do
    local code
    code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:${GITLAB_LOCAL_PORT}/users/sign_in" || true)"
    if [ "${code}" = "200" ] || [ "${code}" = "302" ]; then
      return 0
    fi

    if [ "${SECONDS}" -ge "${deadline}" ]; then
      log_error "GitLab API/UI did not become ready in time."
      tail -n 40 /tmp/gitlab-pf.log 2>/dev/null || true
      exit 1
    fi
    sleep 5
  done
}

gitlab_api_retry() {
  local method="$1"
  local url="$2"
  shift 2

  local attempts=0
  while [ "${attempts}" -lt 30 ]; do
    if curl -sf --max-time 10 -X "${method}" -H "PRIVATE-TOKEN: ${PAT}" "$@" "${url}"; then
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 3
  done
  return 1
}

push_manifests_to_gitlab() {
  local workdir="/tmp/${GITLAB_PROJECT}-repo"
  local remote_url="http://oauth2:${PAT}@localhost:${GITLAB_LOCAL_PORT}/${GITLAB_USER}/${GITLAB_PROJECT}.git"
  rm -rf "${workdir}"
  mkdir -p "${workdir}"

  pushd "${workdir}" >/dev/null
  git init
  git checkout -B main
  git config user.email "${GIT_USER_EMAIL}"
  git config user.name "${GIT_USER_NAME}"
  git remote remove origin >/dev/null 2>&1 || true
  git remote add origin "${remote_url}"

  if git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
    git fetch origin main
    git reset --hard origin/main
  fi

  cp "${REPO_ROOT}/p3/confs/deployment.yaml" "${workdir}/"
  cp "${REPO_ROOT}/p3/confs/service.yaml" "${workdir}/"

  git add .
  if git diff --cached --quiet; then
    log_info "No manifest changes to commit"
  else
    git commit -m "initial manifests"
  fi
  git push -u origin main
  popd >/dev/null

  log_success "Manifests pushed to local GitLab"
}

configure_argocd_and_deploy_app() {
  log_info "Starting port-forward for Argo CD API..."
  start_argocd_port_forward

  local admin_pw
  admin_pw=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

  argocd login "localhost:${ARGOCD_LOCAL_PORT}" --insecure --username admin --password "${admin_pw}"
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

  log_info "Waiting for a running pod behind service 'wil-playground'..."
  local deadline=$((SECONDS + 300))
  while true; do
    if kubectl get endpoints wil-playground -n dev -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | grep -q .; then
      break
    fi

    if [ "${SECONDS}" -ge "${deadline}" ]; then
      log_error "Timed out waiting for wil-playground endpoints."
      kubectl get pods -n dev
      kubectl describe svc wil-playground -n dev || true
      exit 1
    fi

    kubectl get pods -n dev --no-headers 2>/dev/null || true
    sleep 5
  done

  log_info "Port-forwarding app to localhost:8888 (Ctrl+C to stop)..."
  stop_port_forward_if_running "kubectl port-forward svc/wil-playground -n dev 8888:8888"
  free_local_port_if_busy 8888
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
