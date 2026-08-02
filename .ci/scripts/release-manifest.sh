#!/usr/bin/env sh
# release-manifest.sh
# --------------------------------------------------------------------------
# Generates the release artifact manifest (.ci/out/release-manifest.md) from
# the current environment contract. Kept OUT of run-stage.sh so the manifest
# format lives in one place (mirrors the round-1 "externalize scripts" rule).
# LOCAL ONLY — never pushes images, never touches git.
#
# Inputs (env, with project defaults):
#   PET_COMPOSE_PROJECT_NAME (default pet-adoption)
#   PET_APP_ENV              (default staging)
#   PET_RELEASE_TAG          (default local)
# Output:
#   .ci/out/release-manifest.md
# --------------------------------------------------------------------------
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

PET_COMPOSE_PROJECT_NAME="${PET_COMPOSE_PROJECT_NAME:-pet-adoption}"
PET_APP_ENV="${PET_APP_ENV:-staging}"
PET_RELEASE_TAG="${PET_RELEASE_TAG:-local}"

# Tag rule (round-3): <project>-<env>-<release-tag>. See consistency-audit.md
# for the migration note away from the round-1 "<env>-<tag>" form.
TAG="${PET_COMPOSE_PROJECT_NAME}-${PET_APP_ENV}-${PET_RELEASE_TAG}"
BACKEND_IMAGE="${PET_COMPOSE_PROJECT_NAME}-backend"
FRONTEND_IMAGE="${PET_COMPOSE_PROJECT_NAME}-frontend"

OUT_DIR=".ci/out"
OUT_FILE="${OUT_DIR}/release-manifest.md"
mkdir -p "${OUT_DIR}"

{
  echo "# Release Manifest (generated)"
  echo ""
  echo "- Generated for: PET_APP_ENV=\`${PET_APP_ENV}\`"
  echo "- Project name : \`${PET_COMPOSE_PROJECT_NAME}\`"
  echo "- Release tag  : \`${PET_RELEASE_TAG}\`"
  echo ""
  echo "## Images"
  echo ""
  echo "| service | image | release tag rule |"
  echo "| --- | --- | --- |"
  echo "| backend  | \`${BACKEND_IMAGE}\`  | \`${TAG}\` |"
  echo "| frontend | \`${FRONTEND_IMAGE}\` | \`${TAG}\` |"
  echo ""
  echo "Tag rule: \`\${PET_COMPOSE_PROJECT_NAME}-\${PET_APP_ENV}-\${PET_RELEASE_TAG}\`"
  echo ""
  echo "## Key compose files"
  echo ""
  echo "- docker-compose.yml (demo base)"
  echo "- docker-compose.ci.yml (ci overlay)"
  echo "- docker-compose.staging.yml (staging overlay)"
  echo ""
  echo "## Key env example"
  echo ""
  echo "- .ci/config/env.staging.example"
  echo ""
  echo "## Key healthcheck scripts"
  echo ""
  echo "- .ci/scripts/backend-healthcheck.sh"
  echo "- .ci/scripts/frontend-healthcheck.sh"
} > "${OUT_FILE}"

echo "[release-manifest] wrote ${OUT_FILE}"
