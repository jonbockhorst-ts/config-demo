#!/usr/bin/env bash
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-v2.12.6}"
CLUSTER_NAME="${CLUSTER_NAME:-eso-config-demo}"
KUBE_CONTEXT="${KUBE_CONTEXT:-k3d-${CLUSTER_NAME}}"

kubectl --context "${KUBE_CONTEXT}" create namespace argocd --dry-run=client -o yaml | kubectl --context "${KUBE_CONTEXT}" apply -f -
kubectl --context "${KUBE_CONTEXT}" apply -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl --context "${KUBE_CONTEXT}" rollout status deployment/argocd-server -n argocd --timeout=300s
kubectl --context "${KUBE_CONTEXT}" rollout status deployment/argocd-repo-server -n argocd --timeout=300s
kubectl --context "${KUBE_CONTEXT}" rollout status statefulset/argocd-application-controller -n argocd --timeout=300s
