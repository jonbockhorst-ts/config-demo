#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-eso-config-demo}"
KUBE_CONTEXT="${KUBE_CONTEXT:-k3d-${CLUSTER_NAME}}"

if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "${CLUSTER_NAME}"; then
  echo "k3d cluster '${CLUSTER_NAME}' already exists"
  exit 0
fi

k3d cluster create "${CLUSTER_NAME}" --wait
kubectl config use-context "${KUBE_CONTEXT}" >/dev/null
