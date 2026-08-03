#!/usr/bin/env bash
# .ci/scripts/release.sh
# Stage driver: release-preparation gates. Does NOT push images, does NOT run
# any git command. Three gates (declared in .ci/release.yml):
#
#   image_exists      : backend/frontend images exist locally under the
#                       environment tag rule (<project>-<svc>:<PET_APP_ENV>).
#   health_gate       : exec the externalized backend/frontend healthcheck
#                       scripts inside the running target-env containers
#                       (default target env = staging; override PET_APP_ENV).
#   artifact_manifest : validate compose config + dist archive, then render
#                       .ci/out/release-manifest.md from the tracked template.
#
# Usage:
#   bash .ci/scripts/release.sh
# Env:
#   PET_APP_ENV             default staging (the release target environment)
#   PET_COMPOSE_PROJECT_NAME default pet-adoption
#   PET_RELEASE_TAG         default = PET_APP_ENV
#   PET_VITE_API_URL        default per env
#   RELEASE_SKIP_HEALTH     set to "true" to skip the live health gate
#                           (e.g. when validating artifacts without a stack).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${ROOT_DIR}"
# shellcheck source=lib_compose.sh
source "${SCRIPT_DIR}/lib_compose.sh"

# Release targets staging by default (quasi-production validation).
PET_APP_ENV="${PET_APP_ENV:-staging}"
PET_COMPOSE_PROJECT_NAME="${PET_COMPOSE_PROJECT_NAME:-pet-adoption}"
PET_RELEASE_TAG="${PET_RELEASE_TAG:-$(default_release_tag)}"
PET_VITE_API_URL="${PET_VITE_API_URL:-$(default_vite_api_url)}"
RELEASE_SKIP_HEALTH="${RELEASE_SKIP_HEALTH:-false}"
export PET_COMPOSE_PROJECT_NAME PET_APP_ENV

compose_files_for_env

BACKEND_IMAGE="${PET_COMPOSE_PROJECT_NAME}-backend:${PET_RELEASE_TAG}"
FRONTEND_IMAGE="${PET_COMPOSE_PROJECT_NAME}-frontend:${PET_RELEASE_TAG}"
MANIFEST=".ci/out/release-manifest.md"
MANIFEST_TEMPLATE=".ci/release-manifest.template.md"
DIST_ARCHIVE=".ci/out/frontend-dist.tar.gz"

mkdir -p .ci/out

echo "[release] target env : ${PET_APP_ENV}"
echo "[release] project     : ${PET_COMPOSE_PROJECT_NAME}"
echo "[release] tag         : ${PET_RELEASE_TAG}"
echo "[release] images      : ${BACKEND_IMAGE}, ${FRONTEND_IMAGE}"
echo "[release] compose     : ${COMPOSE_FILES[*]}"

gate_failed=0
fail() { echo "[release] GATE FAILED: $1" >&2; gate_failed=1; }

# --- Gate: artifact_manifest (pre) : validate compose config + dist archive ---
echo ""
echo "[release] == gate: artifact_manifest (compose + dist) =="
if docker compose -p "${PET_COMPOSE_PROJECT_NAME}" "${COMPOSE_FILES[@]}" config >/dev/null; then
  echo "[release] compose config: OK"
else
  fail "compose config invalid"
fi
if [ -f "${DIST_ARCHIVE}" ]; then
  echo "[release] dist archive: ${DIST_ARCHIVE} OK"
else
  fail "missing dist archive ${DIST_ARCHIVE} (run build.sh first)"
fi

# --- Gate: image_exists ---
echo ""
echo "[release] == gate: image_exists =="
for img in "${BACKEND_IMAGE}" "${FRONTEND_IMAGE}"; do
  if docker image inspect "${img}" >/dev/null 2>&1; then
    echo "[release] image exists: ${img}"
  else
    fail "image not found locally: ${img} (run build.sh for PET_APP_ENV=${PET_APP_ENV})"
  fi
done

# --- Gate: health_gate ---
echo ""
echo "[release] == gate: health_gate =="
if [ "${RELEASE_SKIP_HEALTH}" = "true" ]; then
  echo "[release] health gate SKIPPED (RELEASE_SKIP_HEALTH=true)"
else
  for svc in backend frontend; do
    if run_service_healthcheck "${svc}"; then
      echo "[release] health OK: ${svc}"
    else
      fail "health check failed for ${svc} (is the ${PET_APP_ENV} stack up? try: docker compose ${COMPOSE_FILES[*]} up -d --wait)"
    fi
  done
fi

if [ "${gate_failed}" -ne 0 ]; then
  echo ""
  echo "[release] one or more gates FAILED; no manifest emitted." >&2
  exit 1
fi

# --- Render release manifest from the tracked template ---
echo ""
echo "[release] rendering manifest -> ${MANIFEST}"

BACKEND_SIZE="$(docker image inspect "${BACKEND_IMAGE}" --format '{{.Size}}')"
FRONTEND_SIZE="$(docker image inspect "${FRONTEND_IMAGE}" --format '{{.Size}}')"
BACKEND_ID="$(docker image inspect "${BACKEND_IMAGE}" --format '{{.Id}}' | sed 's/^sha256://' | cut -c1-12)"
FRONTEND_ID="$(docker image inspect "${FRONTEND_IMAGE}" --format '{{.Id}}' | sed 's/^sha256://' | cut -c1-12)"
DIST_SHA="$(sha256sum "${DIST_ARCHIVE}" | awk '{print $1}')"
BUILD_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
COMPOSE_FILES_STR="${COMPOSE_FILES[*]}"

# The template uses @@PLACEHOLDER@@ tokens so the tracked template stays free
# of evaluated values. sed substitutes the concrete values at render time.
sed \
  -e "s|@@BUILD_TIME@@|${BUILD_TIME}|g" \
  -e "s|@@PET_APP_ENV@@|${PET_APP_ENV}|g" \
  -e "s|@@PET_COMPOSE_PROJECT_NAME@@|${PET_COMPOSE_PROJECT_NAME}|g" \
  -e "s|@@PET_RELEASE_TAG@@|${PET_RELEASE_TAG}|g" \
  -e "s|@@PET_VITE_API_URL@@|${PET_VITE_API_URL}|g" \
  -e "s|@@COMPOSE_FILES@@|${COMPOSE_FILES_STR}|g" \
  -e "s|@@BACKEND_IMAGE@@|${BACKEND_IMAGE}|g" \
  -e "s|@@FRONTEND_IMAGE@@|${FRONTEND_IMAGE}|g" \
  -e "s|@@BACKEND_ID@@|${BACKEND_ID}|g" \
  -e "s|@@FRONTEND_ID@@|${FRONTEND_ID}|g" \
  -e "s|@@BACKEND_SIZE@@|${BACKEND_SIZE}|g" \
  -e "s|@@FRONTEND_SIZE@@|${FRONTEND_SIZE}|g" \
  -e "s|@@DIST_ARCHIVE@@|${DIST_ARCHIVE}|g" \
  -e "s|@@DIST_SHA@@|${DIST_SHA}|g" \
  "${MANIFEST_TEMPLATE}" > "${MANIFEST}"

echo "[release] ALL GATES PASSED. manifest:"
cat "${MANIFEST}"
