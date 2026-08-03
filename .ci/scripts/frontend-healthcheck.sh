#!/bin/sh
# Frontend liveness probe for Pet Adoption Platform.
# Polls the Nginx /health endpoint using wget (busybox).
# Configurable via environment variables:
#   HEALTH_HOST      (default: 127.0.0.1)
#   HEALTH_PORT      (default: 80)
#   HEALTH_PATH      (default: /health)
#   HEALTH_RETRIES   (default: 10)
#   HEALTH_INTERVAL  (default: 2, seconds)
#   HEALTH_TIMEOUT   (default: 5, seconds)

set -eu

HOST="${HEALTH_HOST:-127.0.0.1}"
PORT="${HEALTH_PORT:-80}"
PATH_="${HEALTH_PATH:-/health}"
RETRIES="${HEALTH_RETRIES:-10}"
INTERVAL="${HEALTH_INTERVAL:-2}"
TIMEOUT="${HEALTH_TIMEOUT:-5}"
URL="http://${HOST}:${PORT}${PATH_}"

attempt=1
while [ "$attempt" -le "$RETRIES" ]; do
  if wget -q -O /dev/null -T "$TIMEOUT" "$URL"; then
    echo "[frontend-healthcheck] OK: $URL (attempt ${attempt})"
    exit 0
  fi
  echo "[frontend-healthcheck] retry ${attempt}/${RETRIES}: waiting on ${URL}..." >&2
  attempt=$((attempt + 1))
  sleep "$INTERVAL"
done

echo "[frontend-healthcheck] FAILED after ${RETRIES} attempts: ${URL}" >&2
exit 1
