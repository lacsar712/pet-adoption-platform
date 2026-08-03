#!/bin/sh
# Stage: test
# Runs two independently selectable gates:
#   unit  — backend jest (mongodb-memory-server) + eslint, frontend eslint.
#           Executed on the CI job/host with Node 20 (PET_NODE_VERSION).
#           Does NOT start the db service; tests/setup.js spins up an
#           in-process MongoMemoryServer so there is no port contention.
#           Optional coverage existence check when PET_COVERAGE_GATE=true:
#           runs `npm run test:coverage` and asserts coverage/lcov.info exists.
#           No coverage threshold is enforced (no business-test gaming).
#   smoke — brings up the compose stack for the selected PET_APP_ENV (ci or
#           staging), waits for health, then execs the round-1 external
#           healthcheck scripts inside the backend/frontend containers.
#
# Usage:
#   sh .ci/scripts/stage-test.sh [unit|smoke|all]
#   (or set PET_TEST_KIND=unit|smoke|all)
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
NPM_REGISTRY="https://registry.npmmirror.com"

# On Windows Git Bash/MSYS, prevent automatic conversion of container-internal
# paths like /ci/scripts/*.sh into Windows paths. Harmless (ignored) on Linux.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

cd "$ROOT_DIR"

TEST_KIND="${1:-${PET_TEST_KIND:-all}}"
PET_APP_ENV="${PET_APP_ENV:-ci}"
PET_COMPOSE_PROJECT_NAME="${PET_COMPOSE_PROJECT_NAME:-pet-adoption}"
PET_NODE_VERSION="${PET_NODE_VERSION:-20}"
PET_COVERAGE_GATE="${PET_COVERAGE_GATE:-false}"
export PET_APP_ENV PET_COMPOSE_PROJECT_NAME

run_unit() {
  if command -v node >/dev/null 2>&1; then
    echo "==> [test/unit] Node runtime: $(node -v) (expected v${PET_NODE_VERSION}.x)"
  else
    echo "==> [test/unit] WARNING: node not found on PATH; unit gate requires Node ${PET_NODE_VERSION} on the CI job/host." >&2
  fi
  echo "==> [test/unit] backend  workdir=backend  steps: npm ci -> npm run lint -> npm test (jest + mongodb-memory-server)"
  cd "$ROOT_DIR/backend"
  npm ci --registry="$NPM_REGISTRY"
  npm run lint
  npm test

  if [ "$PET_COVERAGE_GATE" = "true" ]; then
    echo "==> [test/unit] coverage gate ON: npm run test:coverage + existence check"
    npm run test:coverage
    if [ ! -f "$ROOT_DIR/backend/coverage/lcov.info" ]; then
      echo "ERROR: coverage gate failed — coverage/lcov.info was not produced" >&2
      exit 1
    fi
    echo "==> [test/unit] coverage report present: backend/coverage/lcov.info"
  else
    echo "==> [test/unit] coverage gate OFF (set PET_COVERAGE_GATE=true to enable)"
  fi

  echo "==> [test/unit] frontend workdir=frontend steps: npm ci -> npm run lint"
  cd "$ROOT_DIR/frontend"
  npm ci --registry="$NPM_REGISTRY"
  npm run lint
}

compose_files() {
  files="-f docker-compose.yml"
  case "$PET_APP_ENV" in
    demo) ;;
    ci) files="$files -f docker-compose.ci.yml" ;;
    staging)
      files="$files -f docker-compose.staging.yml"
      if [ -f ".ci/config/env.staging" ]; then
        files="$files --env-file .ci/config/env.staging"
      fi
      ;;
    *)
      echo "ERROR: unknown PET_APP_ENV=$PET_APP_ENV (expected demo|ci|staging)" >&2
      exit 1
      ;;
  esac
  echo "$files"
}

run_smoke() {
  FILES="$(compose_files)"
  echo "==> [test/smoke] PET_APP_ENV=$PET_APP_ENV bringing stack up and waiting for healthy"
  echo "==> [test/smoke] compose files: $FILES"

  # --wait blocks until all containers with healthcheck are healthy (or fail).
  # shellcheck disable=SC2086
  docker compose $FILES -p "$PET_COMPOSE_PROJECT_NAME" up -d --build --wait

  echo "==> [test/smoke] invoking round-1 healthcheck scripts inside containers"
  # shellcheck disable=SC2086
  docker compose $FILES -p "$PET_COMPOSE_PROJECT_NAME" exec -T \
    backend sh /ci/scripts/backend-healthcheck.sh
  # shellcheck disable=SC2086
  docker compose $FILES -p "$PET_COMPOSE_PROJECT_NAME" exec -T \
    frontend sh /ci/scripts/frontend-healthcheck.sh

  echo "==> [test/smoke] OK — stack left running; down it with:"
  echo "    docker compose $FILES -p $PET_COMPOSE_PROJECT_NAME down"
}

case "$TEST_KIND" in
  unit) run_unit ;;
  smoke) run_smoke ;;
  all) run_unit; run_smoke ;;
  *)
    echo "ERROR: unknown TEST_KIND=$TEST_KIND (expected unit|smoke|all)" >&2
    exit 1
    ;;
esac

echo "==> [test] done ($TEST_KIND)"
