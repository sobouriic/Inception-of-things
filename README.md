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

## What to push to public GitHub repo

Push the whole `p3` folder, including:

- `p3/confs/app/deployment.yaml`
- `p3/confs/app/service.yaml`
- `p3/confs/application.yaml`
- `p3/confs/namespace.yaml`
- `p3/scripts/install.sh`
- `p3/scripts/cluster.sh`
- `p3/scripts/verify.sh`

Argo CD is configured to deploy from:

- repo: `https://github.com/sobouriic/sobouric-inception.git`
- path: `p3/confs/app`

## Run from beginning

```bash
cd ~/Desktop/Inception-of-things/p3
bash scripts/install.sh
newgrp docker
bash scripts/cluster.sh
bash scripts/verify.sh
```

Open UI:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then browse to `https://localhost:8080` and login with:

- user: `admin`
- password from:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

## Mandatory v1 -> v2 demo

Edit image tag in `p3/confs/app/deployment.yaml`:

- from `wil42/playground:v1`
- to `wil42/playground:v2`

Then push:

```bash
cd ~/Desktop/Inception-of-things
git add p3/confs/app/deployment.yaml
git commit -m "p3: switch app to v2"
git push

```

Argo CD auto-syncs, then verify:

```bash
# Bonus - Local GitLab + Argo CD

Goal: keep the Part 3 flow, but use a local GitLab repository as Argo CD source.

## Concept

- Part 3 proves GitOps with GitHub.
- Bonus proves the same GitOps flow with local GitLab.
- Argo CD must sync from local GitLab, then update app from v1 to v2 after a commit/push.

## Files

- `scripts/install.sh`: install Helm and helpers.
- `scripts/setup_gitlab.sh`: install local GitLab in namespace `gitlab` via Helm.
- `scripts/switch_argocd_to_gitlab.sh`: configure Argo CD repo credentials and apply GitLab-based Application.
- `scripts/verify.sh`: checks for bonus.
- `confs/gitlab-namespace.yaml`: dedicated namespace `gitlab`.
- `confs/application-gitlab-template.yaml`: Argo CD Application template using GitLab repo URL.

## Run order

1. Ensure mandatory Part 3 works first.
2. Install bonus tools:
   - `bash bonus/scripts/install.sh`
3. Install GitLab in cluster:
   - `bash bonus/scripts/setup_gitlab.sh`
4. In GitLab UI, create a project and push your `deployment.yaml` + `service.yaml`.
5. Create a GitLab access token (scope: `read_repository`).
6. Switch Argo CD source from GitHub to GitLab:
   - `bash bonus/scripts/switch_argocd_to_gitlab.sh <gitlab_repo_url> <gitlab_username> <token>`
7. Verify:
   - `bash bonus/scripts/verify.sh`
8. Demo v1 -> v2:
   - update image tag in GitLab repo, commit/push.
   - verify app updates in Argo CD and `curl http://localhost:8888/`.


curl http://localhost:8888/
```
# Bonus - Local GitLab + Argo CD

Goal: keep the Part 3 flow, but use a local GitLab repository as Argo CD source.

## Concept

- Part 3 proves GitOps with GitHub.
- Bonus proves the same GitOps flow with local GitLab.
- Argo CD must sync from local GitLab, then update app from v1 to v2 after a commit/push.

## Files

- `scripts/install.sh`: install Helm and helpers.
- `scripts/setup_gitlab.sh`: install local GitLab in namespace `gitlab` via Helm.
- `scripts/switch_argocd_to_gitlab.sh`: configure Argo CD repo credentials and apply GitLab-based Application.
- `scripts/verify.sh`: checks for bonus.
- `confs/gitlab-namespace.yaml`: dedicated namespace `gitlab`.
- `confs/application-gitlab-template.yaml`: Argo CD Application template using GitLab repo URL.

## Run order

1. Ensure mandatory Part 3 works first.
2. Install bonus tools:
   - `bash bonus/scripts/install.sh`
3. Install GitLab in cluster:
   - `bash bonus/scripts/setup_gitlab.sh`
4. In GitLab UI, create a project and push your `deployment.yaml` + `service.yaml`.
5. Create a GitLab access token (scope: `read_repository`).
6. Switch Argo CD source from GitHub to GitLab:
   - `bash bonus/scripts/switch_argocd_to_gitlab.sh <gitlab_repo_url> <gitlab_username> <token>`
7. Verify:
   - `bash bonus/scripts/verify.sh`
8. Demo v1 -> v2:
   - update image tag in GitLab repo, commit/push.
   - verify app updates in Argo CD and `curl http://localhost:8888/`.
