#!/bin/sh
# ============================================================================
# pipeline.sh —— 流水线总入口（薄调度器）
# 只按 .ci/pipeline.yml 声明的 include 顺序调度各阶段 YAML，
# 本身不包含任何阶段的具体命令（命令只存在于 build/test/release.yml 中）。
#
# 用法：
#   sh .ci/scripts/pipeline.sh                          # build -> test -> release
#   PET_CI_STAGES="build" sh .ci/scripts/pipeline.sh    # 只跑 build
#   PET_CI_STAGES="test"  sh .ci/scripts/pipeline.sh    # 只跑 test（全部门禁）
#   PET_CI_STAGES="build test" sh .ci/scripts/pipeline.sh
#   PET_CI_STAGES="test" PET_CI_GATES="unit" sh .ci/scripts/pipeline.sh   # 只跑 unit 门禁
#   PET_CI_STAGES="test" PET_CI_GATES="smoke" sh .ci/scripts/pipeline.sh  # 只跑 smoke 门禁
# ============================================================================
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

STAGES="${PET_CI_STAGES:-build test release}"
GATES="${PET_CI_GATES:-}"

for stage in $STAGES; do
  sh .ci/scripts/run-stage.sh ".ci/${stage}.yml" "$GATES"
done

echo "[pipeline] all stages finished: $STAGES ${GATES:+(gates: $GATES)}"
