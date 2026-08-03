#!/bin/sh
# Frontend liveness probe.
# Probes ${HEALTH_PATH} on ${HEALTH_HOST}:${HEALTH_PORT} using busybox wget,
# which is pre-installed in nginx:alpine.
#
# Tuneable parameters (env):
#   HEALTH_HOST      default 127.0.0.1
#   HEALTH_PORT      default 80
#   HEALTH_PATH      default /health
#   HEALTH_RETRIES   default 5
#   HEALTH_INTERVAL  default 2 (seconds)
set -eu

HEALTH_HOST="${HEALTH_HOST:-127.0.0.1}"
HEALTH_PORT="${HEALTH_PORT:-80}"
HEALTH_PATH="${HEALTH_PATH:-/health}"
HEALTH_RETRIES="${HEALTH_RETRIES:-5}"
HEALTH_INTERVAL="${HEALTH_INTERVAL:-2}"

attempt=1
while [ "$attempt" -le "$HEALTH_RETRIES" ]; do
  if wget -q -O /dev/null "http://${HEALTH_HOST}:${HEALTH_PORT}${HEALTH_PATH}" 2>/dev/null; then
    exit 0
  fi
  sleep "$HEALTH_INTERVAL"
  attempt=$((attempt + 1))
done
exit 1
