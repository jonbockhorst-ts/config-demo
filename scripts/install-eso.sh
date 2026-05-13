#!/usr/bin/env bash
set -euo pipefail

ESO_VERSION="${ESO_VERSION:-0.14.4}"
CLUSTER_NAME="${CLUSTER_NAME:-eso-config-demo}"
KUBE_CONTEXT="${KUBE_CONTEXT:-k3d-${CLUSTER_NAME}}"

helm repo add external-secrets https://charts.external-secrets.io >/dev/null
helm repo update external-secrets >/dev/null

helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace \
  --version "${ESO_VERSION}" \
  --set installCRDs=true \
  --kube-context "${KUBE_CONTEXT}"

kubectl --context "${KUBE_CONTEXT}" rollout status deployment/external-secrets -n external-secrets-system --timeout=300s
kubectl --context "${KUBE_CONTEXT}" rollout status deployment/external-secrets-webhook -n external-secrets-system --timeout=300s
kubectl --context "${KUBE_CONTEXT}" rollout status deployment/external-secrets-cert-controller -n external-secrets-system --timeout=300s
