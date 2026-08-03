#!/usr/bin/env bash
# .ci/scripts/build.sh
# Stage driver: build. Builds backend + frontend images with docker compose,
# enforcing npm ci and the npmmirror registry via Dockerfile ARGs, and archives
# the rendered frontend dist for the release stage.
#
# This script does not contain business logic; it is the executable counterpart
# of .ci/build.yml.
#
# PET_APP_ENV: demo | ci | staging
# PET_VITE_API_URL defaults: demo/ci -> /api, staging -> http://localhost:8731

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${ROOT_DIR}"
# shellcheck source=lib_compose.sh
source "${SCRIPT_DIR}/lib_compose.sh"

PET_APP_ENV="${PET_APP_ENV:-demo}"
PET_COMPOSE_PROJECT_NAME="${PET_COMPOSE_PROJECT_NAME:-pet-adoption}"
PET_RELEASE_TAG="${PET_RELEASE_TAG:-$(default_release_tag)}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
PET_VITE_API_URL="${PET_VITE_API_URL:-$(default_vite_api_url)}"

compose_files_for_env

echo "[build] PET_APP_ENV=${PET_APP_ENV}"
echo "[build] project=${PET_COMPOSE_PROJECT_NAME} tag=${PET_RELEASE_TAG}"
echo "[build] VITE_API_URL=${PET_VITE_API_URL}"
echo "[build] NPM_REGISTRY=${NPM_REGISTRY}"
echo "[build] compose files: ${COMPOSE_FILES[*]}"

mkdir -p .ci/out

export PET_APP_ENV PET_COMPOSE_PROJECT_NAME PET_VITE_API_URL PET_RELEASE_TAG NPM_REGISTRY

echo "[build] validating compose config..."
docker compose -p "${PET_COMPOSE_PROJECT_NAME}" \
  "${COMPOSE_FILES[@]}" config >/dev/null

echo "[build] building images..."
docker compose -p "${PET_COMPOSE_PROJECT_NAME}" \
  "${COMPOSE_FILES[@]}" build \
  --build-arg VITE_API_URL="${PET_VITE_API_URL}" \
  --build-arg NPM_REGISTRY="${NPM_REGISTRY}"

echo "[build] collecting frontend dist artifact..."
FRONTEND_IMAGE="${PET_COMPOSE_PROJECT_NAME}-frontend:${PET_RELEASE_TAG}"
CID="$(docker create "${FRONTEND_IMAGE}")"
trap 'docker rm -f "${CID}" >/dev/null 2>&1 || true' EXIT
rm -rf .ci/out/frontend-dist .ci/out/frontend-dist.tar.gz
docker cp "${CID}:/usr/share/nginx/html" .ci/out/frontend-dist
tar -czf .ci/out/frontend-dist.tar.gz -C .ci/out frontend-dist
rm -rf .ci/out/frontend-dist
docker rm -f "${CID}" >/dev/null 2>&1 || true
trap - EXIT

echo "[build] done. images:"
docker images --format '  {{.Repository}}:{{.Tag}}  {{.Size}}' | grep "${PET_COMPOSE_PROJECT_NAME}-" || true
echo "[build] artifact: .ci/out/frontend-dist.tar.gz"
