#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_URL="${REPO_URL:-}"
CLUSTER_NAME="${CLUSTER_NAME:-eso-config-demo}"
KUBE_CONTEXT="${KUBE_CONTEXT:-k3d-${CLUSTER_NAME}}"

if [[ -z "${REPO_URL}" ]]; then
  echo "REPO_URL must be set to the GitHub repository URL Argo should watch"
  exit 1
fi

"${ROOT_DIR}/scripts/setup-k3d.sh"
"${ROOT_DIR}/scripts/install-argocd.sh"
"${ROOT_DIR}/scripts/install-eso.sh"
"${ROOT_DIR}/scripts/build-and-load-image.sh"

kubectl --context "${KUBE_CONTEXT}" create namespace eso-seed --dry-run=client -o yaml | kubectl --context "${KUBE_CONTEXT}" apply -f -
kubectl --context "${KUBE_CONTEXT}" create namespace demo --dry-run=client -o yaml | kubectl --context "${KUBE_CONTEXT}" apply -f -

kubectl --context "${KUBE_CONTEXT}" apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: databases-postgres-demo
  namespace: eso-seed
type: Opaque
stringData:
  host: postgres.demo.internal
  port: "5432"
  username: app_user
  password: super-secret-password
---
apiVersion: v1
kind: Secret
metadata:
  name: databases-questdb-demo
  namespace: eso-seed
type: Opaque
stringData:
  host: questdb.demo.internal
  port: "8812"
  username: admin
  password: quest-secret-password
---
apiVersion: v1
kind: Secret
metadata:
  name: auth-jwt-demo
  namespace: eso-seed
type: Opaque
stringData:
  secret: demo-jwt-secret-value
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: eso-reader
  namespace: eso-seed
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: eso-reader
  namespace: eso-seed
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["authorization.k8s.io"]
    resources: ["selfsubjectrulesreviews"]
    verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: eso-reader
  namespace: eso-seed
subjects:
  - kind: ServiceAccount
    name: eso-reader
    namespace: eso-seed
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: eso-reader
EOF

TOKEN="$(kubectl --context "${KUBE_CONTEXT}" -n eso-seed create token eso-reader)"

kubectl --context "${KUBE_CONTEXT}" -n demo create secret generic eso-kubernetes-store-token \
  --from-literal=token="${TOKEN}" \
  --dry-run=client \
  -o yaml | kubectl --context "${KUBE_CONTEXT}" apply -f -

sed "s|REPO_URL_PLACEHOLDER|${REPO_URL}|g" "${ROOT_DIR}/apps/demo.yaml" | kubectl --context "${KUBE_CONTEXT}" apply -f -

echo
echo "Bootstrap submitted."
echo "Cluster context: ${KUBE_CONTEXT}"
echo "Watch sync with: kubectl --context ${KUBE_CONTEXT} get applications -n argocd"
echo "Check the app with: kubectl --context ${KUBE_CONTEXT} logs deploy/demo-app -n demo"
