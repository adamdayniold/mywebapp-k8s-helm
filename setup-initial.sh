#!/bin/bash
set -e

echo "🚀 Starting argocd installation"

# # 1. Add Helm repositories
# echo "📦 Adding Helm repositories..."
# helm repo add jetstack https://charts.jetstack.io                      # Cert-Manager
helm repo add sealed-secrets https://bitnami.github.io/sealed-secrets # Sealed Secrets
# helm repo add autoscalers https://cowboysysop.github.io/charts          # VPA (autoscaling.k8s.io/v1)
helm repo add argo https://argoproj.github.io/argo-helm                  # Argo CD
# helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ # metric server
helm repo update

# 2. Create Namespaces
# echo "📂 Creating namespaces..."
# kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace kube-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# kubectl create namespace nginx-gateway --dry-run=client -o yaml | kubectl apply -f -

# 3. Install Gateway API standard CRDs (gateway.networking.k8s.io/v1)
# echo "🌐 Installing Gateway API CRDs..."
# kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# 4. Install NGINX Gateway Fabric (Handles gatewayClassName: nginx)
# echo "🚦 Installing NGINX Gateway Fabric..."
# helm upgrade --install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
#   --namespace nginx-gateway

# 5. Install Cert-Manager (cert-manager.io/v1)
# echo "🔒 Installing Cert-Manager..."
# helm upgrade --install cert-manager jetstack/cert-manager \
#   --namespace cert-manager \
#   --set crds.enabled=true

# 6. Install Sealed Secrets Controller (bitnami.com/v1alpha1)
echo "🔐 Installing Sealed Secrets..."
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system

# 7. Install Vertical Pod Autoscaler for autoscaling.k8s.io/v1 CRDs
# echo "📈 Installing Vertical Pod Autoscaler (VPA)..."
# helm upgrade --install vpa autoscalers/vertical-pod-autoscaler \
#   --namespace kube-system

# 8. Install Metric Server for VPA and HPA
# echo "Installing Metric server"
# helm upgrade --install metrics-server metrics-server/metrics-server \
#   --namespace kube-system \
#   --set args="{--kubelet-insecure-tls=true}"

# kubectl patch deployment metrics-server -n kube-system --type='json' \
#   -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# 8. Install Argo CD
echo "🐙 Installing Argo CD..."
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd

echo "⏳ Waiting for Sealed Secrets controller to be ready..."
kubectl rollout status deployment sealed-secrets -n kube-system --timeout=120s

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

echo "🎉 Initial setup is done!"