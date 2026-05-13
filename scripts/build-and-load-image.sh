#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-eso-config-demo}"
IMAGE_NAME="${IMAGE_NAME:-eso-config-demo:local}"

docker build -t "${IMAGE_NAME}" "${ROOT_DIR}/app"
k3d image import "${IMAGE_NAME}" -c "${CLUSTER_NAME}"
