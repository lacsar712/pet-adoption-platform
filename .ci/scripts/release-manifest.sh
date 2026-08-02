#!/bin/sh
# ============================================================================
# release-manifest.sh —— 生成发布归档清单 .ci/out/release-manifest.md
# 列出：镜像名与 tag 规则、关键 compose 文件、关键 env example、
# 关键 healthcheck 脚本路径。全部取自本轮约定，禁止包含真实密钥。
# ============================================================================
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

PROJECT="${PET_COMPOSE_PROJECT_NAME:-pet-adoption}"
APP_ENV="${PET_APP_ENV:-staging}"
IMAGE_TAG="${PET_IMAGE_TAG:-ci-local}"
OUT_DIR=".ci/out"
OUT="$OUT_DIR/release-manifest.md"

mkdir -p "$OUT_DIR"

{
  echo "# Release Manifest（自动生成，请勿手改）"
  echo
  echo "- 生成时间（UTC）：$(date -u '+%Y-%m-%d %H:%M:%S')"
  echo "- 环境：PET_APP_ENV=${APP_ENV}"
  echo
  echo "## 镜像"
  echo
  echo "| 服务 | 构建产物（compose 命名） | 发布 tag |"
  echo "| --- | --- | --- |"
  echo "| backend | ${PROJECT}-backend:latest | ${PROJECT}-backend:${APP_ENV}-${IMAGE_TAG} |"
  echo "| frontend | ${PROJECT}-frontend:latest | ${PROJECT}-frontend:${APP_ENV}-${IMAGE_TAG} |"
  echo
  echo "tag 规则：\`\${PET_COMPOSE_PROJECT_NAME}-<service>:\${PET_APP_ENV}-\${PET_IMAGE_TAG}\`"
  echo
  echo "## 关键 compose 文件"
  echo
  echo "- docker-compose.yml（demo 基础文件）"
  echo "- docker-compose.ci.yml（CI 覆盖）"
  echo "- docker-compose.staging.yml（staging 覆盖）"
  echo
  echo "## 关键 env example"
  echo
  echo "- .ci/config/env.staging.example"
  echo
  echo "## 关键 healthcheck 脚本"
  echo
  echo "- .ci/scripts/backend-healthcheck.sh（后端 /health）"
  echo "- .ci/scripts/frontend-healthcheck.sh（前端 /healthz）"
} > "$OUT"

echo "[release-manifest] written: $OUT"
