#!/usr/bin/env bash
# .ci/scripts/lib_compose.sh
# Shared helpers sourced by build.sh / test.sh / release.sh so the environment
# matrix lives in exactly one place.
#
# Supported PET_APP_ENV: demo | ci | staging
#
# Usage (after sourcing):
#   compose_files_for_env        # sets COMPOSE_FILES array
#   default_vite_api_url         # echoes per-env VITE_API_URL
#   default_release_tag          # echoes per-env image tag (defaults to PET_APP_ENV)
#   run_service_healthcheck SVC  # exec the externalized healthcheck in container SVC

compose_files_for_env() {
  case "${PET_APP_ENV:-demo}" in
    demo)
      COMPOSE_FILES=(-f docker-compose.yml)
      ;;
    ci)
      COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.ci.yml)
      ;;
    staging)
      COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.staging.yml)
      ;;
    *)
      echo "[lib_compose] ERROR: PET_APP_ENV must be demo|ci|staging, got '${PET_APP_ENV}'" >&2
      return 1
      ;;
  esac
}

# Default PET_VITE_API_URL per environment. staging gets an absolute backend
# URL; demo/ci keep the /api reverse-proxy prefix.
default_vite_api_url() {
  case "${PET_APP_ENV:-demo}" in
    staging) echo "http://localhost:8731" ;;
    *)       echo "/api" ;;
  esac
}

# Image tag rule (stable across rounds):
#   repository = ${PET_COMPOSE_PROJECT_NAME}-<service>
#   tag        = ${PET_RELEASE_TAG}, defaulting to ${PET_APP_ENV}
# Examples: pet-adoption-backend:demo, pet-adoption-frontend:staging
default_release_tag() {
  echo "${PET_RELEASE_TAG:-${PET_APP_ENV:-demo}}"
}

# Run the externalized healthcheck script for a service inside its container.
# Uses the project-scoped compose invocation so it works even when no host
# ports are published (ci). Caller must have already exported
# PET_COMPOSE_PROJECT_NAME and called compose_files_for_env.
#
# Usage: run_service_healthcheck backend|frontend
run_service_healthcheck() {
  local svc="$1"
  case "${svc}" in
    backend)  local script="/tmp/backend-healthcheck.sh" ;;
    frontend) local script="/tmp/frontend-healthcheck.sh" ;;
    *)
      echo "[lib_compose] ERROR: unknown service '${svc}'" >&2
      return 1
      ;;
  esac
  docker compose -p "${PET_COMPOSE_PROJECT_NAME}" "${COMPOSE_FILES[@]}" \
    exec -T "${svc}" sh "${script}"
}
