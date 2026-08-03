#!/bin/sh
# Backend liveness probe.
# Probes GET ${HEALTH_PATH} on ${HEALTH_HOST}:${HEALTH_PORT} using the Node
# runtime that is guaranteed to exist in the backend image (node:20-slim),
# so no extra OS package (curl/wget) is required.
#
# Tuneable parameters (env):
#   HEALTH_HOST      default 127.0.0.1
#   HEALTH_PORT      default 8731
#   HEALTH_PATH      default /health
#   HEALTH_RETRIES   default 5
#   HEALTH_INTERVAL  default 2 (seconds)
set -eu

HEALTH_HOST="${HEALTH_HOST:-127.0.0.1}"
HEALTH_PORT="${HEALTH_PORT:-8731}"
HEALTH_PATH="${HEALTH_PATH:-/health}"
HEALTH_RETRIES="${HEALTH_RETRIES:-5}"
HEALTH_INTERVAL="${HEALTH_INTERVAL:-2}"

attempt=1
while [ "$attempt" -le "$HEALTH_RETRIES" ]; do
  if HEALTH_HOST="$HEALTH_HOST" HEALTH_PORT="$HEALTH_PORT" HEALTH_PATH="$HEALTH_PATH" node -e '
    const http = require("http");
    const req = http.get(
      {
        host: process.env.HEALTH_HOST,
        port: Number(process.env.HEALTH_PORT),
        path: process.env.HEALTH_PATH,
        timeout: 3000
      },
      (res) => {
        res.resume();
        process.exit(res.statusCode === 200 ? 0 : 1);
      }
    );
    req.on("error", () => process.exit(1));
    req.on("timeout", () => { req.destroy(); process.exit(1); });
  ' 2>/dev/null; then
    exit 0
  fi
  sleep "$HEALTH_INTERVAL"
  attempt=$((attempt + 1))
done
exit 1
