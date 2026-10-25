#!/bin/bash
set -e

echo "fetch key from current cluster"
kubeseal --controller-namespace kube-system --controller-name sealed-secrets --fetch-cert > pub-cert.pem

echo "🔑 Applying encrypted Argo CD SSH deploy key..."
kubeseal --controller-namespace kube-system --controller-name sealed-secrets --format=yaml --cert=pub-cert.pem < ./charts/infrastructure-namespace/templates/secret-repo-raw.yaml > ./charts/infrastructure-namespace/templates/secret.yaml
kubectl apply -f ./charts/infrastructure-namespace/templates/secret.yaml -n argocd

echo "Apply the same secret to application namespace"
kubeseal --controller-namespace kube-system --controller-name sealed-secrets --namespace application --format=yaml --cert=pub-cert.pem < ./charts/mywebapp/templates/secret-raw.yaml > ./charts/mywebapp/templates/secret.yaml

echo "Pushing the code to github!"
git add charts/infrastructure-namespace/templates/secret.yaml
git add charts/mywebapp/templates/secret.yaml
git commit -m "update secrets" || echo "No changes to commit"
git push

echo "Apply root GitOps"
kubectl apply -f ./argocd/root.yaml