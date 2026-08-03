#!/bin/sh
# Backend liveness probe for Pet Adoption Platform.
# Uses Node.js built-in http module (no extra system packages required on node:20-slim).
# Configurable via environment variables:
#   HEALTH_HOST      (default: 127.0.0.1)
#   HEALTH_PORT      (default: 8731)
#   HEALTH_PATH      (default: /health)
#   HEALTH_RETRIES   (default: 10)
#   HEALTH_INTERVAL  (default: 2, seconds)
#   HEALTH_TIMEOUT   (default: 5, seconds)

set -eu

HOST="${HEALTH_HOST:-127.0.0.1}"
PORT="${HEALTH_PORT:-8731}"
PATH_="${HEALTH_PATH:-/health}"
RETRIES="${HEALTH_RETRIES:-10}"
INTERVAL="${HEALTH_INTERVAL:-2}"
TIMEOUT="${HEALTH_TIMEOUT:-5}"

attempt=1
while [ "$attempt" -le "$RETRIES" ]; do
  if node -e "
    const http = require('http');
    const req = http.get({ host: '${HOST}', port: ${PORT}, path: '${PATH_}', timeout: (${TIMEOUT} * 1000) }, (res) => {
      process.exit(res.statusCode >= 200 && res.statusCode < 400 ? 0 : 1);
    });
    req.on('error', () => process.exit(1));
    req.on('timeout', () => { req.destroy(); process.exit(1); });
  " 2>/dev/null; then
    echo "[backend-healthcheck] OK: http://${HOST}:${PORT}${PATH_} (attempt ${attempt})"
    exit 0
  fi
  echo "[backend-healthcheck] retry ${attempt}/${RETRIES}: waiting on http://${HOST}:${PORT}${PATH_}..." >&2
  attempt=$((attempt + 1))
  sleep "$INTERVAL"
done

echo "[backend-healthcheck] FAILED after ${RETRIES} attempts: http://${HOST}:${PORT}${PATH_}" >&2
exit 1
