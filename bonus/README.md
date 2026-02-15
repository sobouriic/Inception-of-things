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
