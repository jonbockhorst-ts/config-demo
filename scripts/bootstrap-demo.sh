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
kubectl --context "${KUBE_CONTEXT}" create namespace demo-override --dry-run=client -o yaml | kubectl --context "${KUBE_CONTEXT}" apply -f -

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
  name: databases-postgres-demo-readonly
  namespace: eso-seed
type: Opaque
stringData:
  host: postgres-readonly.demo.internal
  port: "5432"
  username: readonly_user
  password: readonly-secret-password
---
apiVersion: v1
kind: Secret
metadata:
  name: databases-chart-demo
  namespace: eso-seed
type: Opaque
stringData:
  host: postgres-chart.demo.internal
  port: "5432"
  username: chart_user
  password: chart-secret-password
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
kind: Secret
metadata:
  name: temporal-demo
  namespace: eso-seed
type: Opaque
stringData:
  apiKey: temporal-demo-api-key
---
apiVersion: v1
kind: Secret
metadata:
  name: api-marketdata-demo
  namespace: eso-seed
type: Opaque
stringData:
  apiKey: marketdata-demo-api-key
---
apiVersion: v1
kind: Secret
metadata:
  name: api-strapi-demo
  namespace: eso-seed
type: Opaque
stringData:
  token: strapi-demo-token
---
apiVersion: v1
kind: Secret
metadata:
  name: api-stripe-demo
  namespace: eso-seed
type: Opaque
stringData:
  apiKey: stripe-demo-api-key
---
apiVersion: v1
kind: Secret
metadata:
  name: elasticsearch-demo
  namespace: eso-seed
type: Opaque
stringData:
  password: elasticsearch-demo-password
  cloudApiKey: elasticsearch-demo-cloud-api-key
---
apiVersion: v1
kind: Secret
metadata:
  name: databases-postgres-demo-override
  namespace: eso-seed
type: Opaque
stringData:
  host: postgres.demo-override.internal
  port: "5432"
  username: app_user
  password: super-secret-password
---
apiVersion: v1
kind: Secret
metadata:
  name: databases-postgres-demo-override-readonly
  namespace: eso-seed
type: Opaque
stringData:
  host: postgres-readonly.demo-override.internal
  port: "5432"
  username: readonly_user
  password: readonly-secret-password
---
apiVersion: v1
kind: Secret
metadata:
  name: databases-chart-demo-override
  namespace: eso-seed
type: Opaque
stringData:
  host: postgres-chart.demo-override.internal
  port: "5432"
  username: chart_user
  password: chart-secret-password
---
apiVersion: v1
kind: Secret
metadata:
  name: auth-jwt-demo-override
  namespace: eso-seed
type: Opaque
stringData:
  secret: demo-override-jwt-secret-value
---
apiVersion: v1
kind: Secret
metadata:
  name: temporal-demo-override
  namespace: eso-seed
type: Opaque
stringData:
  apiKey: temporal-demo-override-api-key
---
apiVersion: v1
kind: Secret
metadata:
  name: api-marketdata-demo-override
  namespace: eso-seed
type: Opaque
stringData:
  apiKey: marketdata-demo-override-api-key
---
apiVersion: v1
kind: Secret
metadata:
  name: api-strapi-demo-override
  namespace: eso-seed
type: Opaque
stringData:
  token: strapi-demo-override-token
---
apiVersion: v1
kind: Secret
metadata:
  name: api-stripe-demo-override
  namespace: eso-seed
type: Opaque
stringData:
  apiKey: stripe-demo-override-api-key
---
apiVersion: v1
kind: Secret
metadata:
  name: elasticsearch-demo-override
  namespace: eso-seed
type: Opaque
stringData:
  password: elasticsearch-demo-override-password
  cloudApiKey: elasticsearch-demo-override-cloud-api-key
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

kubectl --context "${KUBE_CONTEXT}" -n demo-override create secret generic eso-kubernetes-store-token \
  --from-literal=token="${TOKEN}" \
  --dry-run=client \
  -o yaml | kubectl --context "${KUBE_CONTEXT}" apply -f -

apply_demo_application() {
  local app_name="$1"
  local app_path="$2"
  local app_namespace="$3"

  cat <<EOF | kubectl --context "${KUBE_CONTEXT}" apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${app_name}
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    targetRevision: main
    path: ${app_path}
    helm:
      values: |
        topstepx:
          secrets:
            ConnectionStrings:
              Topstep:
                remoteKey: databases-postgres-{{ .Values.config.secretsEnv }}
              TopstepReadOnly:
                remoteKey: databases-postgres-{{ .Values.config.secretsEnv }}-readonly
              Chart:
                remoteKey: databases-chart-{{ .Values.config.secretsEnv }}
            Jwt:
              remoteKey: auth-jwt-{{ .Values.config.secretsEnv }}
            Temporal:
              remoteKey: temporal-{{ .Values.config.secretsEnv }}
            MarketDataApi:
              remoteKey: api-marketdata-{{ .Values.config.secretsEnv }}
            Strapi:
              remoteKey: api-strapi-{{ .Values.config.secretsEnv }}
            Stripe:
              remoteKey: api-stripe-{{ .Values.config.secretsEnv }}
            ElasticSearch:
              remoteKey: elasticsearch-{{ .Values.config.secretsEnv }}
  destination:
    server: https://kubernetes.default.svc
    namespace: ${app_namespace}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
}

apply_demo_application "demo" "envs/demo" "demo"
apply_demo_application "demo-override" "envs/demo-override" "demo-override"

echo
echo "Bootstrap submitted."
echo "Cluster context: ${KUBE_CONTEXT}"
echo "Watch sync with: kubectl --context ${KUBE_CONTEXT} get applications -n argocd"
echo "Check the app with: kubectl --context ${KUBE_CONTEXT} logs deploy/demo-app -n demo"
echo "Check the override app with: kubectl --context ${KUBE_CONTEXT} logs deploy/demo-app -n demo-override"
