#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <gitlab_repo_url> <gitlab_username> <gitlab_token>"
  echo "Example: $0 http://gitlab.127.0.0.1.nip.io/root/iot-bonus.git root glpat-xxxx"
  exit 1
fi

REPO_URL="$1"
REPO_USER="$2"
REPO_TOKEN="$3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
TEMPLATE="${PROJECT_DIR}/confs/application-gitlab-template.yaml"
TMP_APP="$(mktemp)"

sed "s|REPLACE_REPO_URL|${REPO_URL}|g" "${TEMPLATE}" > "${TMP_APP}"

echo "[BONUS] Registering GitLab repo credentials in Argo CD..."
kubectl create secret generic repo-gitlab \
  --namespace argocd \
  --from-literal=type=git \
  --from-literal=url="${REPO_URL}" \
  --from-literal=username="${REPO_USER}" \
  --from-literal=password="${REPO_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label secret repo-gitlab -n argocd argocd.argoproj.io/secret-type=repository --overwrite

echo "[BONUS] Applying Argo CD Application pointing to GitLab..."
kubectl apply -f "${TMP_APP}"
kubectl annotate application dev-app -n argocd argocd.argoproj.io/refresh=hard --overwrite

rm -f "${TMP_APP}"
echo "[BONUS] Argo CD now tracks GitLab repo: ${REPO_URL}"
