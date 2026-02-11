# Part 3 (K3d + Argo CD)

## What to push to public GitHub repo

Push the whole `p3` folder, including:

- `p3/confs/app/deployment.yaml`
- `p3/confs/app/service.yaml`
- `p3/confs/application.yaml`
- `p3/confs/namespace.yaml`
- `p3/scripts/install.sh`
- `p3/scripts/setup_cluster.sh`
- `p3/scripts/verify.sh`

Argo CD is configured to deploy from:

- repo: `https://github.com/sobouriic/sobouric-inception.git`
- path: `p3/confs/app`

## Run from beginning

```bash
cd ~/Desktop/Inception-of-things/p3
bash scripts/install.sh
newgrp docker
bash scripts/setup_cluster.sh
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
curl http://localhost:8888/
```
