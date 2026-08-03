#!/bin/sh
# Stage: build
# Build backend + frontend images with docker compose.
# Enforces lockfile discipline and uses the npmmirror registry (already baked
# into the Dockerfiles via npm config) so CI builds are reproducible.
#
# PET_APP_ENV selects the compose overlay:
#   demo    -> docker-compose.yml
#   ci      -> docker-compose.yml + docker-compose.ci.yml
#   staging -> docker-compose.yml + docker-compose.staging.yml
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

PET_APP_ENV="${PET_APP_ENV:-demo}"
PET_COMPOSE_PROJECT_NAME="${PET_COMPOSE_PROJECT_NAME:-pet-adoption}"
export PET_APP_ENV PET_COMPOSE_PROJECT_NAME

echo "==> [build] PET_APP_ENV=$PET_APP_ENV project=$PET_COMPOSE_PROJECT_NAME"
echo "==> [build] PET_VITE_API_URL=${PET_VITE_API_URL:-<compose default per env>}"

for lockfile in \
  "$ROOT_DIR/backend/package-lock.json" \
  "$ROOT_DIR/frontend/package-lock.json"; do
  if [ ! -f "$lockfile" ]; then
    echo "ERROR: lockfile missing: $lockfile" >&2
    echo "       Run 'npm install' locally and commit package-lock.json." >&2
    exit 1
  fi
done

COMPOSE_FILES="-f $ROOT_DIR/docker-compose.yml"
case "$PET_APP_ENV" in
  demo) ;;
  ci) COMPOSE_FILES="$COMPOSE_FILES -f $ROOT_DIR/docker-compose.ci.yml" ;;
  staging) COMPOSE_FILES="$COMPOSE_FILES -f $ROOT_DIR/docker-compose.staging.yml" ;;
  *)
    echo "ERROR: unknown PET_APP_ENV=$PET_APP_ENV (expected demo|ci|staging)" >&2
    exit 1
    ;;
esac

# shellcheck disable=SC2086
docker compose $COMPOSE_FILES -p "$PET_COMPOSE_PROJECT_NAME" build

echo "==> [build] done"
