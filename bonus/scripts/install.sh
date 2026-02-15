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

MIN_FREE_GB="${MIN_FREE_GB:-12}"

ensure_docker_access() {
  if ! docker info >/dev/null 2>&1; then
    log_error "Docker daemon is not reachable for current user."
    log_error "Run: sudo systemctl enable --now docker && sudo usermod -aG docker \$USER && newgrp docker"
    exit 1
  fi
}

repair_docker_tmp_dir() {
  if [ ! -d /var/lib/docker/tmp ]; then
    log_warn "Docker tmp directory is missing, recreating /var/lib/docker/tmp"
    sudo mkdir -p /var/lib/docker/tmp
    sudo chown root:root /var/lib/docker/tmp
    sudo chmod 711 /var/lib/docker/tmp
    sudo systemctl restart docker || true
    sleep 2
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
    log_error "Cleanup and retry: docker system prune -af --volumes"
    exit 1
  fi

  local free_gb
  free_gb="$(awk "BEGIN {printf \"%.1f\", ${free_kb}/1024/1024}")"
  log_info "Disk check OK on ${mount_target}: ${free_gb}GB free (min ${MIN_FREE_GB}GB)"
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log_info "Docker already installed"
    return
  fi

  log_info "Installing Docker..."
  if curl -fsSL https://get.docker.com -o /tmp/get-docker.sh && sh /tmp/get-docker.sh; then
    rm -f /tmp/get-docker.sh
    sudo systemctl enable --now docker || true
    sudo usermod -aG docker "${USER}" || true
    sudo chmod 666 /var/run/docker.sock || true
    log_success "Docker installed via get.docker.com"
    return
  fi

  log_warn "get.docker.com install failed, falling back to distro package docker.io"
  rm -f /tmp/get-docker.sh || true
  sudo apt-get update
  sudo apt-get install -y docker.io
  sudo systemctl enable --now docker || true
  sudo usermod -aG docker "${USER}" || true
  sudo chmod 666 /var/run/docker.sock || true
  log_success "Docker installed via docker.io package"
}

install_git() {
  if command -v git >/dev/null 2>&1; then
    log_info "Git already installed"
    return
  fi

  log_info "Installing Git..."
  sudo apt-get update
  sudo apt-get install -y git
  log_success "Git installed"
}

install_k3d() {
  if command -v k3d >/dev/null 2>&1; then
    log_info "k3d already installed"
    return
  fi

  log_info "Installing k3d..."
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  log_success "k3d installed"
}

install_kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    log_info "kubectl already installed"
    return
  fi

  log_info "Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
  log_success "kubectl installed"
}

install_helm() {
  if command -v helm >/dev/null 2>&1; then
    log_info "Helm already installed"
    return
  fi

  log_info "Installing Helm..."
  if timeout 300 bash -c 'curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash'; then
    log_success "Helm installed via get-helm script"
    return
  fi

  log_warn "get-helm script timed out/failed, trying GitHub release tarball fallback"
  local helm_version="v3.20.0"
  local arch="amd64"
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  curl -fsSL "https://github.com/helm/helm/releases/download/${helm_version}/helm-${helm_version}-linux-${arch}.tar.gz" -o "${tmp_dir}/helm.tgz"
  tar -xzf "${tmp_dir}/helm.tgz" -C "${tmp_dir}"
  sudo install -m 0755 "${tmp_dir}/linux-${arch}/helm" /usr/local/bin/helm
  rm -rf "${tmp_dir}"
  log_success "Helm installed via fallback tarball"
}

main() {
  log_info "=== Bonus step 1/2: Installing prerequisites ==="
  install_docker
  install_git
  install_k3d
  install_kubectl
  install_helm
  ensure_docker_access
  repair_docker_tmp_dir
  check_free_disk_space
  log_success "Prerequisites are ready"
  log_info "Run next: bash bonus/scripts/deploy.sh"
}

main
