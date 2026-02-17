# Inception of Things

This repository contains my implemented parts:
- `p1`: K3s + Vagrant (2 VMs)
- `p3`: K3d + Argo CD (GitOps from GitHub)
- `bonus`: local GitLab + Argo CD (GitOps from local GitLab)

## Part 1 (`p1`) - K3s + Vagrant

### What it does
- Creates 2 CentOS Stream 9 VMs:
  - `sobouricS` (server/control plane) at `192.168.56.110`
  - `sobouricSW` (agent/worker) at `192.168.56.111`
- Installs K3s server on `sobouricS`
- Installs K3s agent on `sobouricSW`
- Joins both nodes in one cluster

### Files
- `p1/Vagrantfile`
- `p1/scripts/install_k3s_server.sh`
- `p1/scripts/install_k3s_agent.sh`
- `p1/scripts/clean-vagrant.sh`
- `p1/confs/k3s_token`

### Run
```bash
cd p1
vagrant up
```

### Check
```bash
vagrant ssh sobouricS -c "hostname"
vagrant ssh sobouricSW -c "hostname"
vagrant ssh sobouricS -c "ip a show eth1"
vagrant ssh sobouricSW -c "ip a show eth1"
vagrant ssh sobouricS -c "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes -o wide"
```

## Part 3 (`p3`) - K3d + Argo CD

### What it does
- Installs required tools (Docker, kubectl, k3d)
- Creates a k3d cluster
- Creates `argocd` and `dev` namespaces
- Installs Argo CD in `argocd`
- Applies Argo CD `Application` that deploys manifests from GitHub into `dev`
- Exposes app on local `http://localhost:8888`

### Files
- `p3/confs/namespace.yaml`
- `p3/confs/application.yaml`
- `p3/confs/deployment.yaml`
- `p3/confs/service.yaml`
- `p3/scripts/install.sh`
- `p3/scripts/cluster.sh`
- `p3/scripts/run_all.sh`
- `p3/scripts/verify.sh`
- `p3/scripts/argocd_ui.sh`
- `p3/scripts/clean.sh`

### Run
```bash
cd p3
bash scripts/install.sh
newgrp docker
bash scripts/cluster.sh
bash scripts/verify.sh
```

Shortcut:
```bash
cd p3
bash scripts/run_all.sh
```

### Argo CD UI
```bash
bash scripts/argocd_ui.sh
```
Or manually:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### Mandatory demo (`v1 -> v2`)
1. Edit `p3/confs/deployment.yaml` image from `wil42/playground:v1` to `wil42/playground:v2`
2. Commit and push to the Git repository used by Argo CD
3. Verify sync and result:
```bash
kubectl get applications -n argocd -o wide
curl http://localhost:8888/
```

## Bonus (`bonus`) - Local GitLab + Argo CD

### What it does
- Deploys local GitLab in namespace `gitlab`
- Keeps Part 3 flow working with `argocd` and `dev`
- Pushes app manifests to local GitLab repository
- Switches Argo CD application source to local GitLab
- Keeps GitOps version switch (`v1 -> v2`) working

### Files
- `bonus/confs/gitlab-values-light.yaml`
- `bonus/confs/argo-cd.yaml`
- `bonus/confs/application.yaml`
- `bonus/scripts/install.sh`
- `bonus/scripts/deploy.sh`
- `bonus/scripts/verify.sh`
- `bonus/scripts/clean.sh`

### Prerequisite
Part 3 should work first.

### Run
```bash
bash bonus/scripts/install.sh
bash bonus/scripts/deploy.sh
```

Optional:
```bash
GITLAB_VALUES_FILE=/path/to/custom-values.yaml bash bonus/scripts/deploy.sh
```

### Verify
```bash
bash bonus/scripts/verify.sh
curl http://localhost:8888/
```

### Bonus demo (`v1 -> v2`)
1. Update image tag in local GitLab repo from `v1` to `v2`
2. Commit and push
3. Confirm Argo CD sync and app output update

## Cleanup

Part 1:
```bash
bash p1/scripts/clean-vagrant.sh
```

Part 3:
```bash
bash p3/scripts/clean.sh
```

Bonus:
```bash
bash bonus/scripts/clean.sh
```
