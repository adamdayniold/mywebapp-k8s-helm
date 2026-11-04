#!/usr/bin/env bash
# Create the local k3d cluster and bootstrap Flux.
# Needs GITHUB_TOKEN exported (short-lived fine-grained token:
# this repo only, Administration + Contents read/write). Revoke it afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER=simple-app-cluster
KEY_BACKUP=secrets/sealed-secrets-key.yaml

: "${GITHUB_TOKEN:?export GITHUB_TOKEN first}"

if ! k3d cluster list "$CLUSTER" >/dev/null 2>&1; then
  k3d cluster create "$CLUSTER" \
    -p "80:80@loadbalancer" -p "443:443@loadbalancer"
fi

# Restore the old sealing key so existing SealedSecrets still decrypt
# (the controller picks it up when Flux installs it).
if [[ -f "$KEY_BACKUP" ]]; then
  kubectl apply -f "$KEY_BACKUP"
fi

flux bootstrap github \
  --owner=adamdayniold \
  --repository=mywebapp-k8s-helm \
  --branch=main \
  --path=clusters/local-k3d \
  --personal

echo "Done. Run: git pull   (bootstrap pushed a commit)"
echo "Then revoke the GitHub token."
