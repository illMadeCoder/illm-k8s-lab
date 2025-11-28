#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Adding ArgoCD Helm repo..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "Installing ArgoCD..."
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values "$SCRIPT_DIR/argocd/values.yaml" \
  --wait

echo ""
echo "ArgoCD installed. Getting initial admin password..."
echo "Password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo ""
echo "To access the UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Then open: https://localhost:8080"
echo "  Username: admin"
