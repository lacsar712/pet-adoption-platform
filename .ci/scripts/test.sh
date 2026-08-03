#!/usr/bin/env bash
# .ci/scripts/test.sh
# Stage driver: test. Executable counterpart of .ci/test.yml.
#
# Two quality gates:
#   unit  : backend jest unit tests + eslint inside a disposable node:20-slim
#           container. Tests use mongodb-memory-server; NO real MongoDB
#           container is required.
#   smoke : brings up the compose stack for PET_APP_ENV (ci | staging | demo),
#           waits for health, then invokes the externalized
#           backend/frontend-healthcheck.sh scripts against the running
#           containers. The stack is left running; call `down` separately.
#   all   : unit then smoke.
#
# Usage:
#   bash .ci/scripts/test.sh [unit|smoke|all]
# Default gate: unit.
# Env:
#   PET_APP_ENV=demo|ci|staging   (selects compose files for smoke)
#   PET_COMPOSE_PROJECT_NAME      (default pet-adoption)
#   SMOKE_SERVICES                (default "backend frontend"; probes to run)
#   TEST_COVERAGE                 ("true" to run jest with --coverage and assert
#                                  the coverage report exists; default off)
#   COVERAGE_REPORT               (default coverage/coverage-summary.json)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${ROOT_DIR}"
# shellcheck source=lib_compose.sh
source "${SCRIPT_DIR}/lib_compose.sh"

GATE="${1:-unit}"
case "${GATE}" in
  unit|smoke|all) ;;
  *)
    echo "[test] ERROR: gate must be unit|smoke|all, got '${GATE}'" >&2
    exit 1
    ;;
esac

PET_APP_ENV="${PET_APP_ENV:-ci}"
PET_COMPOSE_PROJECT_NAME="${PET_COMPOSE_PROJECT_NAME:-pet-adoption}"
BACKEND_IMAGE="${BACKEND_IMAGE:-docker.m.daocloud.io/library/node:20-slim}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
SMOKE_SERVICES="${SMOKE_SERVICES:-backend frontend}"
TEST_COVERAGE="${TEST_COVERAGE:-false}"
COVERAGE_REPORT="${COVERAGE_REPORT:-coverage/coverage-summary.json}"
CACHE_VOLUME="${PET_COMPOSE_PROJECT_NAME}-backend-node_modules"
MONGOMS_CACHE_VOLUME="${PET_COMPOSE_PROJECT_NAME}-mongombs-cache"

mkdir -p .ci/out

run_unit() {
  echo "[test:unit] image=${BACKEND_IMAGE} registry=${NPM_REGISTRY}"
  echo "[test:unit] using mongodb-memory-server; no real mongo required."
  echo "[test:unit] coverage gate: ${TEST_COVERAGE} (expect ${COVERAGE_REPORT})"

  docker volume create "${CACHE_VOLUME}" >/dev/null
  docker volume create "${MONGOMS_CACHE_VOLUME}" >/dev/null

  JEST_ARGS="--runInBand"
  if [ "${TEST_COVERAGE}" = "true" ]; then
    JEST_ARGS="${JEST_ARGS} --coverage"
  fi

  docker run --rm \
    -v "${ROOT_DIR}/backend:/app" \
    -v "${CACHE_VOLUME}:/app/node_modules" \
    -v "${MONGOMS_CACHE_VOLUME}:/root/.cache/mongodb-binaries" \
    -w /app \
    -e CI=true \
    -e NPM_CONFIG_REGISTRY="${NPM_REGISTRY}" \
    "${BACKEND_IMAGE}" \
    sh -c "
      set -eu
      echo '[test:unit] npm ci...'
      npm ci
      echo '[test:unit] npm run lint...'
      npm run lint
      echo '[test:unit] npm test -- ${JEST_ARGS}...'
      npm test -- ${JEST_ARGS}
    " 2>&1 | tee .ci/out/test-report.txt

  if [ "${TEST_COVERAGE}" = "true" ]; then
    if docker run --rm \
         -v "${ROOT_DIR}/backend:/app" \
         -v "${CACHE_VOLUME}:/app/node_modules" \
         -w /app \
         "${BACKEND_IMAGE}" \
         sh -c "test -f '${COVERAGE_REPORT}'" \
         2>&1 | tee .ci/out/coverage-report.txt; then
      echo "[test:unit] coverage report exists: backend/${COVERAGE_REPORT}" | tee -a .ci/out/coverage-report.txt
    else
      echo "[test:unit] COVERAGE GATE FAILED: ${COVERAGE_REPORT} not generated" >&2
      exit 1
    fi
  fi

  echo "[test:unit] passed. report: .ci/out/test-report.txt"
}

run_smoke() {
  compose_files_for_env
  echo "[test:smoke] PET_APP_ENV=${PET_APP_ENV}"
  echo "[test:smoke] compose files: ${COMPOSE_FILES[*]}"
  echo "[test:smoke] starting stack with --wait (health gating)..."

  docker compose -p "${PET_COMPOSE_PROJECT_NAME}" "${COMPOSE_FILES[@]}" \
    up -d --build --wait

  : > .ci/out/smoke-report.txt
  rc=0
  for svc in ${SMOKE_SERVICES}; do
    echo "[test:smoke] probing ${svc} ..." | tee -a .ci/out/smoke-report.txt
    case "${svc}" in
      backend)
        # Run the backend healthcheck inside the backend container so it
        # reaches 127.0.0.1:8731 and needs no host port publishing.
        if docker compose -p "${PET_COMPOSE_PROJECT_NAME}" "${COMPOSE_FILES[@]}" \
             exec -T backend sh /tmp/backend-healthcheck.sh \
             2>&1 | tee -a .ci/out/smoke-report.txt; then
          echo "[test:smoke] backend OK" | tee -a .ci/out/smoke-report.txt
        else
          echo "[test:smoke] backend FAILED" | tee -a .ci/out/smoke-report.txt
          rc=1
        fi
        ;;
      frontend)
        if docker compose -p "${PET_COMPOSE_PROJECT_NAME}" "${COMPOSE_FILES[@]}" \
             exec -T frontend sh /tmp/frontend-healthcheck.sh \
             2>&1 | tee -a .ci/out/smoke-report.txt; then
          echo "[test:smoke] frontend OK" | tee -a .ci/out/smoke-report.txt
        else
          echo "[test:smoke] frontend FAILED" | tee -a .ci/out/smoke-report.txt
          rc=1
        fi
        ;;
      *)
        echo "[test:smoke] ERROR: unknown service '${svc}'" >&2
        rc=1
        ;;
    esac
  done

  if [ "${rc}" -ne 0 ]; then
    echo "[test:smoke] FAIL. Collecting logs..." >&2
    docker compose -p "${PET_COMPOSE_PROJECT_NAME}" "${COMPOSE_FILES[@]}" \
      logs --tail=100 >&2 || true
    exit "${rc}"
  fi
  echo "[test:smoke] all probes passed. report: .ci/out/smoke-report.txt"
}

case "${GATE}" in
  unit)  run_unit ;;
  smoke) run_smoke ;;
  all)   run_unit; run_smoke ;;
esac
