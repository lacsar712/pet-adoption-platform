#!/usr/bin/env sh
# run-stage.sh <build|test|release>
# --------------------------------------------------------------------------
# Per-stage executor. Holds the CONCRETE commands for one stage, mirroring
# the declarative intent in .ci/build.yml / .ci/test.yml / .ci/release.yml.
# The total entry (pipeline.sh) only dispatches into here — it never carries
# stage commands itself.
#
# Run a single stage directly:
#   sh .ci/scripts/run-stage.sh test
# --------------------------------------------------------------------------
set -eu

STAGE="${1:-}"
if [ -z "${STAGE}" ]; then
  echo "usage: run-stage.sh <build|test|release>" >&2
  exit 2
fi

# Resolve repo root (this script lives in .ci/scripts).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

# --- Environment contract (defaults match the project port convention) ----
export PET_APP_ENV="${PET_APP_ENV:-ci}"
export PET_API_PUBLISH_PORT="${PET_API_PUBLISH_PORT:-8731}"
export PET_WEB_PUBLISH_PORT="${PET_WEB_PUBLISH_PORT:-3731}"
export PET_DB_PUBLISH_PORT="${PET_DB_PUBLISH_PORT:-5731}"
export PET_COMPOSE_PROJECT_NAME="${PET_COMPOSE_PROJECT_NAME:-pet-adoption}"

# PET_VITE_API_URL default depends on the environment matrix:
#   demo/ci  -> "/api"                 (served behind the Nginx reverse proxy)
#   staging  -> "http://localhost:8731" (frontend talks to backend directly)
if [ -z "${PET_VITE_API_URL:-}" ]; then
  case "${PET_APP_ENV}" in
    staging) PET_VITE_API_URL="http://localhost:${PET_API_PUBLISH_PORT}" ;;
    *)       PET_VITE_API_URL="/api" ;;
  esac
fi
export PET_VITE_API_URL

# Select the compose overlay for the active environment (round-1 layering):
#   demo    -> base file only
#   ci      -> base + docker-compose.ci.yml
#   staging -> base + docker-compose.staging.yml
case "${PET_APP_ENV}" in
  demo)    COMPOSE_FILES="-f docker-compose.yml" ;;
  ci)      COMPOSE_FILES="-f docker-compose.yml -f docker-compose.ci.yml" ;;
  staging) COMPOSE_FILES="-f docker-compose.yml -f docker-compose.staging.yml" ;;
  *)
    echo "unknown PET_APP_ENV: ${PET_APP_ENV} (expected demo|ci|staging)" >&2
    exit 2
    ;;
esac

COMPOSE="docker compose -p ${PET_COMPOSE_PROJECT_NAME} ${COMPOSE_FILES}"

stage_build() {
  echo "===> [build] building images (VITE_API_URL=${PET_VITE_API_URL})"
  ${COMPOSE} build --build-arg VITE_API_URL="${PET_VITE_API_URL}"
  echo "===> [build] validating merged compose config"
  ${COMPOSE} config >/dev/null
  # Tag the compose-built images under the round-3 release tag so the
  # release image_exists gate can find them. Compose names built images
  # "<project>-<service>"; we re-tag to "<project>-<service>:<project>-<env>-<tag>".
  TAG="${PET_COMPOSE_PROJECT_NAME}-${PET_APP_ENV}-${PET_RELEASE_TAG:-local}"
  for svc in backend frontend; do
    SRC="${PET_COMPOSE_PROJECT_NAME}-${svc}"
    DST="${PET_COMPOSE_PROJECT_NAME}-${svc}:${TAG}"
    if docker image inspect "${SRC}" >/dev/null 2>&1; then
      docker tag "${SRC}" "${DST}"
      echo "===> [build] tagged ${DST}"
    else
      echo "WARN: expected built image ${SRC} not found; skipping tag" >&2
    fi
  done
  echo "===> [build] done"
}

stage_test() {
  # Gates are space-separated and selected via PET_TEST_GATES (default both).
  #   unit  -> jest + mongodb-memory-server in ./backend (NO real Mongo)
  #   smoke -> bring compose up, run externalized healthcheck probes
  GATES="${PET_TEST_GATES:-unit smoke}"
  echo "===> [test] gates: ${GATES} (PET_APP_ENV=${PET_APP_ENV})"
  for gate in ${GATES}; do
    case "${gate}" in
      unit)  test_gate_unit ;;
      smoke) test_gate_smoke ;;
      *)
        echo "unknown test gate: ${gate} (expected unit|smoke)" >&2
        exit 2
        ;;
    esac
  done
  echo "===> [test] done"
}

# --- unit gate --------------------------------------------------------------
# Workdir: ./backend | Node: 20 (matches base images) | install: npm ci
# Uses jest + mongodb-memory-server; does NOT require a real Mongo service.
# Optional coverage existence check via PET_TEST_COVERAGE=1 (default off):
#   runs jest --coverage and asserts the report file was produced. Does NOT
#   change business tests or enforce a coverage threshold.
test_gate_unit() {
  echo "---> [test:unit] backend lint"
  ( cd backend && npm run lint ) || echo "WARN: lint reported issues (non-fatal)"
  echo "---> [test:unit] npm ci (only if node_modules missing)"
  ( cd backend && { [ -d node_modules ] || npm ci; } )
  if [ "${PET_TEST_COVERAGE:-0}" = "1" ]; then
    echo "---> [test:unit] jest --coverage (report existence check)"
    ( cd backend && NODE_ENV=test npm test -- --coverage )
    REPORT="backend/coverage/lcov-report/index.html"
    ALT="backend/coverage/lcov.info"
    if [ -f "${REPORT}" ] || [ -f "${ALT}" ]; then
      echo "     coverage report present"
    else
      echo "[test:unit] coverage report NOT found under backend/coverage/" >&2
      exit 1
    fi
  else
    echo "---> [test:unit] jest (mongodb-memory-server, no real Mongo)"
    ( cd backend && NODE_ENV=test npm test )
  fi
}

# --- smoke gate -------------------------------------------------------------
# Brings up the compose stack for the active env (ci/staging) and probes
# liveness through the round-1 externalized healthcheck scripts.
test_gate_smoke() {
  echo "---> [test:smoke] starting stack (${PET_APP_ENV})"
  ${COMPOSE} up -d --build
  echo "---> [test:smoke] backend probe (host port ${PET_API_PUBLISH_PORT})"
  HC_HOST=127.0.0.1 HC_PORT="${PET_API_PUBLISH_PORT}" \
    sh .ci/scripts/backend-healthcheck.sh
  echo "---> [test:smoke] frontend probe (host port ${PET_WEB_PUBLISH_PORT})"
  HC_HOST=127.0.0.1 HC_PORT="${PET_WEB_PUBLISH_PORT}" \
    sh .ci/scripts/frontend-healthcheck.sh
  echo "---> [test:smoke] tearing down"
  ${COMPOSE} down -v
}

stage_release() {
  # Release PREPARATION gates. NO image push, NO git. Gates selected via
  # PET_RELEASE_GATES (default all). Order is fixed and meaningful:
  #   validate       -> compose overlays merge cleanly
  #   image_exists   -> frontend/backend images built under the agreed tag
  #   health_gate    -> round-1 healthchecks pass for PET_RELEASE_ENV
  #   artifact_manifest -> generate .ci/out/release-manifest.md
  GATES="${PET_RELEASE_GATES:-validate image_exists health_gate artifact_manifest}"
  echo "===> [release] gates: ${GATES} (PET_APP_ENV=${PET_APP_ENV})"
  for gate in ${GATES}; do
    case "${gate}" in
      validate)          release_gate_validate ;;
      image_exists)      release_gate_image_exists ;;
      health_gate)       release_gate_health ;;
      artifact_manifest) release_gate_manifest ;;
      *)
        echo "unknown release gate: ${gate}" >&2
        exit 2
        ;;
    esac
  done
  echo "===> [release] done"
}

# Round-3 release tag rule: <project>-<env>-<release-tag>.
# (Migrated from round-1 "<env>-<tag>"; see docs/engineering/consistency-audit.md.)
release_tag() {
  echo "${PET_COMPOSE_PROJECT_NAME}-${PET_APP_ENV}-${PET_RELEASE_TAG:-local}"
}

release_gate_validate() {
  echo "---> [release:validate] merging compose overlays"
  ${COMPOSE} config >/dev/null
}

# image_exists: confirm both images were built under the agreed tag. The tag
# is applied at build time via IMAGE_TAG substituted into compose image: fields.
release_gate_image_exists() {
  TAG="$(release_tag)"
  echo "---> [release:image_exists] expecting tag suffix: ${TAG}"
  MISSING=0
  for svc_image in "${PET_COMPOSE_PROJECT_NAME}-backend:${TAG}" \
                   "${PET_COMPOSE_PROJECT_NAME}-frontend:${TAG}"; do
    if docker image inspect "${svc_image}" >/dev/null 2>&1; then
      echo "     found: ${svc_image}"
    else
      echo "     MISSING: ${svc_image}" >&2
      MISSING=1
    fi
  done
  if [ "${MISSING}" -ne 0 ]; then
    echo "[release:image_exists] build images first, e.g.:" >&2
    echo "  PET_APP_ENV=${PET_APP_ENV} PET_RELEASE_TAG=${PET_RELEASE_TAG:-local} sh .ci/scripts/run-stage.sh build" >&2
    exit 1
  fi
}

# health_gate: probe the target env (default staging) via round-1 scripts.
release_gate_health() {
  REL_ENV="${PET_RELEASE_ENV:-staging}"
  echo "---> [release:health_gate] probing env=${REL_ENV}"
  HC_HOST=127.0.0.1 HC_PORT="${PET_API_PUBLISH_PORT}" \
    sh .ci/scripts/backend-healthcheck.sh
  HC_HOST=127.0.0.1 HC_PORT="${PET_WEB_PUBLISH_PORT}" \
    sh .ci/scripts/frontend-healthcheck.sh
}

release_gate_manifest() {
  echo "---> [release:artifact_manifest] generating manifest"
  PET_RELEASE_TAG="${PET_RELEASE_TAG:-local}" sh .ci/scripts/release-manifest.sh
}

case "${STAGE}" in
  build)   stage_build ;;
  test)    stage_test ;;
  release) stage_release ;;
  *)
    echo "unknown stage: ${STAGE} (expected build|test|release)" >&2
    exit 2
    ;;
esac
