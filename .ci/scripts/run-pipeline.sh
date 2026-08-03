#!/usr/bin/env bash
# .ci/scripts/run-pipeline.sh
# Top-level pipeline entry. Invokes stage driver scripts in order. This script
# ONLY schedules stages; it must not duplicate concrete build/test/release
# commands. Each stage delegates to its own *.sh (declared in .ci/pipeline.yml).
#
# Usage:
#   bash .ci/scripts/run-pipeline.sh [--stages LIST] [--test-gate GATE]
#
#   --stages LIST     Comma-separated, ordered subset of:
#                     build,test,release. Default: build,test,release.
#                     Examples:
#                       --stages build
#                       --stages test                 # only run the test stage
#                       --stages build,test           # build + test (skip release)
#   --test-gate GATE  Passed through to the test stage: unit|smoke|all.
#                     Default: all (when test is in the stage list).
#
# Env (see .ci/pipeline.yml):
#   PET_APP_ENV=demo|ci|staging

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${ROOT_DIR}"

PET_APP_ENV="${PET_APP_ENV:-demo}"
export PET_APP_ENV

STAGES="build,test,release"
TEST_GATE="all"

while [ $# -gt 0 ]; do
  case "$1" in
    --stages)
      STAGES="$2"; shift 2 ;;
    --test-gate)
      TEST_GATE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,20p' "$0"; exit 0 ;;
    *)
      echo "[pipeline] ERROR: unknown argument '$1'" >&2
      exit 1 ;;
  esac
done

IFS=',' read -r -a STAGE_LIST <<< "${STAGES}"

echo "============================================================"
echo " Pet Adoption Platform pipeline"
echo " PET_APP_ENV=${PET_APP_ENV}"
echo " stages: ${STAGES}"
if printf '%s\n' "${STAGE_LIST[@]}" | grep -qx "test"; then
  echo " test-gate: ${TEST_GATE}"
fi
echo "============================================================"

for stage in "${STAGE_LIST[@]}"; do
  stage="$(echo "${stage}" | tr -d '[:space:]')"
  [ -z "${stage}" ] && continue
  script="${SCRIPT_DIR}/${stage}.sh"
  echo ""
  echo ">>> [pipeline] stage '${stage}' -> ${script}"

  case "${stage}" in
    build|release)
      bash "${script}"
      ;;
    test)
      bash "${script}" "${TEST_GATE}"
      ;;
    *)
      echo "[pipeline] ERROR: unknown stage '${stage}'" >&2
      exit 1
      ;;
  esac
  echo "<<< [pipeline] stage '${stage}' OK"
done

echo ""
echo "============================================================"
echo " Pipeline completed successfully."
echo "============================================================"
