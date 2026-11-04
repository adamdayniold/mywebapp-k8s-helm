#!/usr/bin/env bash
# Seal raw secrets in secrets/ into committed SealedSecret manifests.
# Usage: scripts/seal-secrets.sh [--refresh-cert]
set -euo pipefail
cd "$(dirname "$0")/.."

CONTROLLER_NS=kube-system
CONTROLLER_NAME=kube-system-sealed-secrets
CERT=secrets/pub-cert.pem

# raw file (gitignored) -> sealed output (committed)
declare -A TARGETS=(
  [secrets/mongo-secret-raw.yaml]=charts/mywebapp/templates/secret.yaml
  [secrets/grafana-admin-raw.yaml]=monitoring/grafana-admin-secret.yaml
)

if [[ "${1:-}" == "--refresh-cert" || ! -f "$CERT" ]]; then
  echo "Fetching sealing cert from the cluster..."
  kubeseal --controller-namespace "$CONTROLLER_NS" \
           --controller-name "$CONTROLLER_NAME" \
           --fetch-cert > "$CERT"
fi

for raw in "${!TARGETS[@]}"; do
  out=${TARGETS[$raw]}
  if [[ ! -f "$raw" ]]; then
    echo "skip: $raw not found"
    continue
  fi
  kubeseal --cert "$CERT" --format yaml < "$raw" > "$out"
  echo "sealed: $raw -> $out"
done
