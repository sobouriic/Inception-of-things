# Inception of Things - Part 1 (K3s + Vagrant)

This folder sets up 2 VMs with Vagrant:
- `sobouricS` (server/control-plane) -> `192.168.56.110`
- `sobouricSW` (agent/worker) -> `192.168.56.111`

Both machines run CentOS Stream 9 and are provisioned with K3s.

## Files

- `Vagrantfile` - defines both VMs and network
- `scripts/install_k3s_server.sh` - installs and configures K3s server
- `scripts/install_k3s_agent.sh` - installs and configures K3s agent

## Run

From this folder:

```bash
cd ~/Desktop/Inception-of-things/p1
vagrant destroy -f
vagrant up
```

## Mandatory Checks (Evaluation)

### 1) SSH access to both VMs

```bash
vagrant ssh sobouricS
vagrant ssh sobouricSW
```

### 2) Hostnames

```bash
vagrant ssh sobouricS -c "hostname"
vagrant ssh sobouricSW -c "hostname"
```

Expected:
- `sobouricS`
- `sobouricSW`

### 3) `eth1` IP addresses

```bash
vagrant ssh sobouricS -c "ip a show eth1"
vagrant ssh sobouricSW -c "ip a show eth1"
```

Expected:
- server has `192.168.56.110`
- worker has `192.168.56.111`

### 4) Cluster has both nodes

Run on server:

```bash
vagrant ssh sobouricS -c "sudo /usr/local/bin/kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes -o wide"
```

Expected: 2 nodes in `Ready` state (`sobourics` and `sobouricsw`).

## Troubleshooting

- Vagrant lock error:
  - Find old process: `ps -ef | grep -E "vagrant|ruby"`
  - Kill stuck PID, then retry `vagrant up` / `vagrant destroy -f`
- If cluster shows only one node:
  - Re-provision worker: `vagrant provision sobouricSW`
  - Check agent logs: `vagrant ssh sobouricSW -c "sudo journalctl -u k3s-agent -n 100 --no-pager"`

# Part 3 (K3d + Argo CD)

This part runs a local K3d cluster, installs Argo CD, and deploys the app in namespace `dev`.

## Repository content (Part 3)

- `p3/confs/deployment.yaml`
- `p3/confs/service.yaml`
- `p3/confs/namespace.yaml`
- `p3/confs/application.yaml`
- `p3/scripts/install.sh`
- `p3/scripts/cluster.sh`
- `p3/scripts/run_all.sh`
- `p3/scripts/verify.sh`
- `p3/scripts/argocd_ui.sh`

Argo CD source is defined in `p3/confs/application.yaml`.

## Run from scratch

```bash
cd ~/Desktop/Inception-of-things/p3
bash scripts/install.sh
newgrp docker
bash scripts/cluster.sh
bash scripts/verify.sh
```

Shortcut:

```bash
cd ~/Desktop/Inception-of-things/p3
bash scripts/run_all.sh
```

## Access Argo CD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open `https://localhost:8080` and login with:
- username: `admin`
- password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

## Mandatory v1 -> v2 demo

1. Update the app image tag in `p3/confs/deployment.yaml`:
   - from `wil42/playground:v1`
   - to `wil42/playground:v2`
2. Commit and push:

```bash
cd ~/Desktop/Inception-of-things
git add p3/confs/deployment.yaml
git commit -m "p3: switch app to v2"
git push
```

3. Verify sync and app response:

```bash
kubectl get applications -n argocd -o wide
curl http://localhost:8888/
```

# Bonus - Local GitLab + Argo CD

Goal: keep the Part 3 flow, but use a local GitLab repository as Argo CD source.

## Concept

- Part 3 proves GitOps with GitHub.
- Bonus proves the same GitOps flow with local GitLab.
- Argo CD must sync from local GitLab, then apply changes (v1 -> v2) after commit/push.

## Bonus files

- `bonus/scripts/install.sh`: installs Helm and required tools.
- `bonus/scripts/setup_gitlab.sh`: installs local GitLab in namespace `gitlab`.
- `bonus/scripts/switch_argocd_to_gitlab.sh`: registers repo credentials and switches Argo CD source.
- `bonus/scripts/verify.sh`: runs bonus checks.
- `bonus/confs/gitlab-namespace.yaml`: namespace for GitLab.
- `bonus/confs/application-gitlab-template.yaml`: Argo CD Application template for GitLab source.

## Run order

1. Complete Part 3 first.
2. Install bonus tools:

```bash
bash bonus/scripts/install.sh
```

3. Install local GitLab:

```bash
bash bonus/scripts/setup_gitlab.sh
```

4. In GitLab UI, create a project and push your app manifests.
5. Create a GitLab token with `read_repository` scope.
6. Switch Argo CD to GitLab:

```bash
bash bonus/scripts/switch_argocd_to_gitlab.sh <gitlab_repo_url> <gitlab_username> <gitlab_token>
```

7. Verify:

```bash
bash bonus/scripts/verify.sh
curl http://localhost:8888/
```

8. Demo update:
- change image tag `v1 -> v2` in the GitLab repo
- commit/push
- confirm Argo CD syncs and app is updated
