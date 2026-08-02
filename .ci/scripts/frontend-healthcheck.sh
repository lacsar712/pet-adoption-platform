#!/usr/bin/env sh
# frontend-healthcheck.sh
# --------------------------------------------------------------------------
# Purpose: probe the pet-adoption frontend (Nginx) for liveness. Hits the
# dedicated /healthz location that Nginx serves directly (no backend needed).
# Kept OUT of the Dockerfile/compose inline command for the same reasons as
# the backend probe.
#
# Configurable via env vars (with sane defaults):
#   HC_HOST      target host                     (default: 127.0.0.1)
#   HC_PORT      target port                     (default: 80)
#   HC_PATH      health path                     (default: /healthz)
#   HC_RETRIES   number of attempts              (default: 10)
#   HC_INTERVAL  seconds to wait between tries   (default: 3)
#   HC_TIMEOUT   per-request timeout in seconds  (default: 3)
#
# Usage (probing published port from host):
#   HC_PORT=3731 sh .ci/scripts/frontend-healthcheck.sh
# Exit code 0 = healthy, non-zero = unhealthy.
# --------------------------------------------------------------------------
set -eu

HC_HOST="${HC_HOST:-127.0.0.1}"
HC_PORT="${HC_PORT:-80}"
HC_PATH="${HC_PATH:-/healthz}"
HC_RETRIES="${HC_RETRIES:-10}"
HC_INTERVAL="${HC_INTERVAL:-3}"
HC_TIMEOUT="${HC_TIMEOUT:-3}"

URL="http://${HC_HOST}:${HC_PORT}${HC_PATH}"

probe() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time "${HC_TIMEOUT}" "${URL}" >/dev/null 2>&1
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T "${HC_TIMEOUT}" -O /dev/null "${URL}" >/dev/null 2>&1
  else
    echo "[frontend-healthcheck] neither curl nor wget available" >&2
    return 127
  fi
}

echo "[frontend-healthcheck] probing ${URL} (retries=${HC_RETRIES}, interval=${HC_INTERVAL}s)"
attempt=1
while [ "${attempt}" -le "${HC_RETRIES}" ]; do
  if probe; then
    echo "[frontend-healthcheck] healthy on attempt ${attempt}"
    exit 0
  fi
  echo "[frontend-healthcheck] attempt ${attempt}/${HC_RETRIES} failed; retrying in ${HC_INTERVAL}s"
  attempt=$((attempt + 1))
  sleep "${HC_INTERVAL}"
done

echo "[frontend-healthcheck] FAILED after ${HC_RETRIES} attempts: ${URL}" >&2
exit 1
