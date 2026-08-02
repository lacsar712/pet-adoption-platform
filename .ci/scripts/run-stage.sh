#!/bin/sh
# ============================================================================
# run-stage.sh —— 阶段执行器：从 .ci/<stage>.yml 中按顺序提取单行 `run:`
# 命令并逐条执行（任一失败即终止，退出码非 0）。
#
# 用法：
#   sh .ci/scripts/run-stage.sh .ci/build.yml           # 执行整个阶段
#   sh .ci/scripts/run-stage.sh .ci/test.yml unit       # 只执行指定 gate
#
# gate 机制：阶段 YAML 可用两个空格缩进的 `gate名:` 分组（见 .ci/test.yml 的
# gates: unit/smoke）；传入第二个参数时只执行该 gate 下的 run 命令。
# 无 gate 的阶段文件（build.yml/release.yml）行为不变。
# ============================================================================
set -eu

STAGE_FILE="${1:?usage: sh .ci/scripts/run-stage.sh <stage-yml> [gate]}"
GATE="${2:-}"
[ -f "$STAGE_FILE" ] || { echo "[run-stage] file not found: $STAGE_FILE" >&2; exit 1; }

echo "[run-stage] ===> $STAGE_FILE ${GATE:+(gate: $GATE)}"

# 提取单行 run 命令（格式约定：缩进的 "run: <cmd>"，多行块 run: | 不支持）。
# awk 跟踪两个空格缩进的 "xxx:" 作为当前 gate 名；指定 GATE 时只输出该组命令。
awk -v want="$GATE" '
  /^  [A-Za-z_-]+:[[:space:]]*$/ { current=$1; sub(/:.*/, "", current); next }
  /^[[:space:]]+run:[[:space:]]+[^|>]/ {
    line=$0
    sub(/^[[:space:]]+run:[[:space:]]+/, "", line)
    if (want == "" || current == want) print line
  }
' "$STAGE_FILE" | while IFS= read -r cmd; do
  echo "[run-stage] + $cmd"
  sh -c "$cmd" || exit 1
done

echo "[run-stage] <=== done: $STAGE_FILE ${GATE:+(gate: $GATE)}"
