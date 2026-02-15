# Bonus - GitLab + Argo CD (Part 3 extension)

This bonus extends Part 3 by using a **local GitLab** repository as Argo CD source.

## Goal

1. Run GitLab locally in namespace `gitlab`.
2. Keep `argocd` and `dev` flow working.
3. Make Argo CD sync the app from local GitLab instead of GitHub.
4. Prove update `v1 -> v2` still works through GitOps.

## Files in this folder

- `scripts/install.sh`: step 1, install/check required tools.
- `scripts/deploy.sh`: step 2, deploy cluster + Argo CD + GitLab + app.
- `scripts/clean.sh`: cleanup script.
- `confs/application.yaml`: Argo CD `Application` pointing to local GitLab repo.
- `confs/argo-cd.yaml`: Argo CD ConfigMap override.

## Prerequisite

Mandatory Part 3 must be valid first.

```bash
bash p3/scripts/run_all.sh
```

## Deploy bonus (2 steps)

From repository root:

```bash
export GIT_USER_EMAIL="your-gitlab-email@example.com"
bash bonus/scripts/install.sh
bash bonus/scripts/deploy.sh
```

Step 1 (`install.sh`) will:
- install/check Docker, k3d, kubectl, Helm, Argo CD

Step 2 (`deploy.sh`) will:
- create namespaces `argocd`, `dev`, `gitlab`
- install local GitLab in `gitlab`
- create/update GitLab project `root/sobouric`
- push `p3/confs/deployment.yaml` and `p3/confs/service.yaml` to that repo
- apply `bonus/confs/argo-cd.yaml` and `bonus/confs/application.yaml`

## Git identity used for bonus

Use your login consistently:

```bash
git config --global user.name "sobouric"
git config --global user.email "<your_gitlab_email>"
```

For bonus authentication and pushes, use **GitLab** credentials/token.

## Validation checklist (defense)

1. Namespace `gitlab` exists.
2. GitLab is reachable locally.
3. Argo CD application points to local GitLab repository.
4. App is synced and healthy in namespace `dev`.
5. Changing image `wil42/playground:v1` to `wil42/playground:v2` in GitLab updates runtime app.

## Cleanup

```bash
bash bonus/scripts/clean.sh
```
