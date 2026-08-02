#!/bin/sh
# ============================================================================
# backend-healthcheck.sh —— 后端存活探测（唯一探测入口，禁止把 curl 长命令
# 内联到 Dockerfile HEALTHCHECK 或 compose YAML 里）
#
# 用法：
#   sh backend-healthcheck.sh [host] [port] [path]
#   或用环境变量：HEALTHCHECK_HOST / HEALTHCHECK_PORT / HEALTHCHECK_PATH /
#                 HEALTHCHECK_RETRIES / HEALTHCHECK_INTERVAL
#
# 参数默认值（面向容器内调用；宿主机调用请显式传参或设环境变量）：
#   host     默认 127.0.0.1（容器内探测自身）
#   port     默认 8731（后端容器内监听端口）
#   path     默认 /health（后端健康端点；经 Nginx 反代时为 /api/health）
#   retries  默认 12 次；compose healthcheck 场景由服务环境变量置为 1，
#            把重试节奏交还给 compose 的 interval/retries，避免双重重试
#   interval 默认 5 秒
#
# 探测工具按 curl -> wget -> node(fetch) 顺序自动降级，
# 保证在 node:20-slim（无 curl/wget）与 nginx:alpine 中都能运行。
# ============================================================================
set -eu

HOST="${HEALTHCHECK_HOST:-${1:-127.0.0.1}}"
PORT="${HEALTHCHECK_PORT:-${2:-8731}}"
PATH_="${HEALTHCHECK_PATH:-${3:-/health}}"
RETRIES="${HEALTHCHECK_RETRIES:-12}"
INTERVAL="${HEALTHCHECK_INTERVAL:-5}"

URL="http://${HOST}:${PORT}${PATH_}"

probe() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsS -o /dev/null -m 5 "$URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O /dev/null -T 5 "$URL"
  elif command -v node >/dev/null 2>&1; then
    node -e "fetch(process.argv[1]).then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" "$URL"
  else
    echo "[backend-healthcheck] no usable http client (curl/wget/node)" >&2
    return 1
  fi
}

attempt=1
while [ "$attempt" -le "$RETRIES" ]; do
  if probe; then
    echo "[backend-healthcheck] OK ${URL} (attempt ${attempt}/${RETRIES})"
    exit 0
  fi
  echo "[backend-healthcheck] waiting ${URL} (attempt ${attempt}/${RETRIES}, retry in ${INTERVAL}s)"
  sleep "$INTERVAL"
  attempt=$((attempt + 1))
done

echo "[backend-healthcheck] FAILED after ${RETRIES} attempts: ${URL}" >&2
exit 1
