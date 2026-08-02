#!/usr/bin/env sh
# backend-healthcheck.sh
# --------------------------------------------------------------------------
# Purpose: probe the pet-adoption backend for liveness. Kept OUT of the
# Dockerfile HEALTHCHECK / compose inline command so that probe path,
# timeout and retry policy can be changed in one place.
#
# Configurable via env vars (with sane defaults):
#   HC_HOST      target host                     (default: 127.0.0.1)
#   HC_PORT      target port                     (default: 8731)
#   HC_PATH      health endpoint path            (default: /health)
#   HC_RETRIES   number of attempts              (default: 10)
#   HC_INTERVAL  seconds to wait between tries   (default: 3)
#   HC_TIMEOUT   per-request timeout in seconds  (default: 3)
#
# Usage:
#   HC_PORT=8731 sh .ci/scripts/backend-healthcheck.sh
# Exit code 0 = healthy, non-zero = unhealthy.
# --------------------------------------------------------------------------
set -eu

HC_HOST="${HC_HOST:-127.0.0.1}"
HC_PORT="${HC_PORT:-8731}"
HC_PATH="${HC_PATH:-/health}"
HC_RETRIES="${HC_RETRIES:-10}"
HC_INTERVAL="${HC_INTERVAL:-3}"
HC_TIMEOUT="${HC_TIMEOUT:-3}"

URL="http://${HC_HOST}:${HC_PORT}${HC_PATH}"

probe() {
  # Prefer curl, fall back to wget (both exist on common node/alpine images).
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time "${HC_TIMEOUT}" "${URL}" >/dev/null 2>&1
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T "${HC_TIMEOUT}" -O /dev/null "${URL}" >/dev/null 2>&1
  else
    echo "[backend-healthcheck] neither curl nor wget available" >&2
    return 127
  fi
}

echo "[backend-healthcheck] probing ${URL} (retries=${HC_RETRIES}, interval=${HC_INTERVAL}s)"
attempt=1
while [ "${attempt}" -le "${HC_RETRIES}" ]; do
  if probe; then
    echo "[backend-healthcheck] healthy on attempt ${attempt}"
    exit 0
  fi
  echo "[backend-healthcheck] attempt ${attempt}/${HC_RETRIES} failed; retrying in ${HC_INTERVAL}s"
  attempt=$((attempt + 1))
  sleep "${HC_INTERVAL}"
done

echo "[backend-healthcheck] FAILED after ${HC_RETRIES} attempts: ${URL}" >&2
exit 1
