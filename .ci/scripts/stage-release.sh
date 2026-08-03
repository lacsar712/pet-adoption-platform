#!/bin/sh
# Stage: release (publish preparation — NO registry push, NO git operations).
#
# Three independently runnable gates (also runnable together via `all`):
#   image_exists     verify <project>-backend:latest and -frontend:latest
#                    were built, then tag them as :<PET_IMAGE_TAG> and re-verify.
#   health_gate      bring up the target env stack (default staging), wait for
#                    healthy, and exec the round-1 external healthcheck scripts
#                    inside backend/frontend containers. Failure => release fail.
#   artifact_manifest validate all three compose configs and render a concrete
#                    release manifest into .ci/out/release-manifest.md from the
#                    committed template docs/engineering/release-manifest.example.md.
#
# Usage:
#   sh .ci/scripts/stage-release.sh [image_exists|health_gate|artifact_manifest|all]
#   (or set PET_RELEASE_GATE=...)
#
# Tag rule (unchanged since round 1):
#   repository : <PET_COMPOSE_PROJECT_NAME>-backend | -frontend
#   floating   : latest
#   release    : <PET_IMAGE_TAG>  (default <PET_APP_ENV>-latest, e.g. staging-latest)
# This deliberately retains the round 1/2 `<project>-<service>:<env>-latest`
# convention instead of switching to a new `<project>-<env>-<service>` form.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# On Windows Git Bash/MSYS, prevent automatic conversion of container-internal
# paths like /ci/scripts/*.sh into Windows paths. Harmless (ignored) on Linux.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

cd "$ROOT_DIR"

PET_APP_ENV="${PET_APP_ENV:-demo}"
PET_COMPOSE_PROJECT_NAME="${PET_COMPOSE_PROJECT_NAME:-pet-adoption}"
PET_IMAGE_TAG="${PET_IMAGE_TAG:-${PET_APP_ENV}-latest}"
PET_RELEASE_ENV="${PET_RELEASE_ENV:-staging}"
OUT_DIR="${PET_OUT_DIR:-$ROOT_DIR/.ci/out}"
export PET_APP_ENV PET_COMPOSE_PROJECT_NAME PET_IMAGE_TAG PET_RELEASE_ENV

BACKEND_IMAGE="${PET_COMPOSE_PROJECT_NAME}-backend"
FRONTEND_IMAGE="${PET_COMPOSE_PROJECT_NAME}-frontend"

gate="${1:-${PET_RELEASE_GATE:-all}}"

compose_files_for() {
  target="$1"
  files="-f docker-compose.yml"
  case "$target" in
    demo) ;;
    ci) files="$files -f docker-compose.ci.yml" ;;
    staging)
      files="$files -f docker-compose.staging.yml"
      if [ -f ".ci/config/env.staging" ]; then
        files="$files --env-file .ci/config/env.staging"
      fi
      ;;
    *)
      echo "ERROR: unknown release env '$target' (expected demo|ci|staging)" >&2
      exit 1
      ;;
  esac
  echo "$files"
}

gate_image_exists() {
  echo "==> [release/image_exists] verifying built images"
  for img in "$BACKEND_IMAGE:latest" "$FRONTEND_IMAGE:latest"; do
    if ! docker image inspect "$img" >/dev/null 2>&1; then
      echo "ERROR: image not found locally: $img" >&2
      echo "       Run the build stage first (sh .ci/scripts/stage-build.sh)." >&2
      exit 1
    fi
    echo "    found: $img"
  done

  echo "==> [release/image_exists] tagging -> $PET_IMAGE_TAG"
  docker tag "$BACKEND_IMAGE:latest" "$BACKEND_IMAGE:$PET_IMAGE_TAG"
  docker tag "$FRONTEND_IMAGE:latest" "$FRONTEND_IMAGE:$PET_IMAGE_TAG"

  for img in "$BACKEND_IMAGE:$PET_IMAGE_TAG" "$FRONTEND_IMAGE:$PET_IMAGE_TAG"; do
    if ! docker image inspect "$img" >/dev/null 2>&1; then
      echo "ERROR: failed to confirm tagged image: $img" >&2
      exit 1
    fi
    echo "    tagged: $img"
  done
}

gate_health() {
  echo "==> [release/health_gate] target env=$PET_RELEASE_ENV"
  FILES="$(compose_files_for "$PET_RELEASE_ENV")"
  echo "    compose: $FILES"

  # Ensure the target stack is up and healthy. No --build: release must run
  # against images already produced by the build stage.
  # shellcheck disable=SC2086
  docker compose $FILES -p "$PET_COMPOSE_PROJECT_NAME" up -d --wait

  echo "==> [release/health_gate] exec round-1 healthcheck scripts in containers"
  # shellcheck disable=SC2086
  docker compose $FILES -p "$PET_COMPOSE_PROJECT_NAME" exec -T \
    backend sh /ci/scripts/backend-healthcheck.sh
  # shellcheck disable=SC2086
  docker compose $FILES -p "$PET_COMPOSE_PROJECT_NAME" exec -T \
    frontend sh /ci/scripts/frontend-healthcheck.sh
  echo "==> [release/health_gate] OK"
}

gate_manifest() {
  echo "==> [release/artifact_manifest] validating compose files"
  docker compose -f docker-compose.yml config -q
  docker compose -f docker-compose.yml -f docker-compose.ci.yml config -q
  docker compose -f docker-compose.yml -f docker-compose.staging.yml config -q

  mkdir -p "$OUT_DIR"
  out="$OUT_DIR/release-manifest.md"
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  image_list="$(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}' \
    | grep -E "^${PET_COMPOSE_PROJECT_NAME}-(backend|frontend):" || true)"

  # Render by substituting placeholders in the committed example template.
  sed \
    -e "s|{{GENERATED_AT}}|$generated_at|g" \
    -e "s|{{PET_APP_ENV}}|$PET_APP_ENV|g" \
    -e "s|{{PET_RELEASE_ENV}}|$PET_RELEASE_ENV|g" \
    -e "s|{{PET_COMPOSE_PROJECT_NAME}}|$PET_COMPOSE_PROJECT_NAME|g" \
    -e "s|{{PET_IMAGE_TAG}}|$PET_IMAGE_TAG|g" \
    -e "s|{{BACKEND_IMAGE}}|$BACKEND_IMAGE|g" \
    -e "s|{{FRONTEND_IMAGE}}|$FRONTEND_IMAGE|g" \
    docs/engineering/release-manifest.example.md > "$out"

  {
    echo ""
    echo "## Local image inventory"
    echo ""
    echo '```'
    if [ -n "$image_list" ]; then
      echo "$image_list"
    else
      echo "(no images matched ${PET_COMPOSE_PROJECT_NAME}-{backend,frontend})"
    fi
    echo '```'
  } >> "$out"

  echo "==> [release/artifact_manifest] written: $out"
}

case "$gate" in
  image_exists) gate_image_exists ;;
  health_gate) gate_health ;;
  artifact_manifest) gate_manifest ;;
  all)
    gate_image_exists
    gate_health
    gate_manifest
    ;;
  *)
    echo "ERROR: unknown release gate '$gate' (expected image_exists|health_gate|artifact_manifest|all)" >&2
    exit 1
    ;;
esac

echo "==> [release] done ($gate)"
