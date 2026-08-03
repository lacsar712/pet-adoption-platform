#!/bin/sh
# Pipeline entrypoint (shell driver).
# This script ONLY dispatches stages in order. It must not contain the
# concrete build/test/release commands — those live in stage-*.sh and are
# declared in .ci/{build,test,release}.yml.
#
# Usage:
#   sh .ci/scripts/run-pipeline.sh [stage ...]
#
#   No args        -> build, test, release (full pipeline)
#   build          -> build only
#   test           -> test only (unit + smoke; override with PET_TEST_KIND)
#   build test     -> build then test (no release)
#   build release  -> build then release (skips test)
#
# Selecting a sub-gate inside the test stage:
#   PET_TEST_KIND=unit|smoke|all  (default all)
#
# Examples:
#   sh .ci/scripts/run-pipeline.sh build
#   PET_TEST_KIND=smoke PET_APP_ENV=ci sh .ci/scripts/run-pipeline.sh test
#   PET_APP_ENV=staging sh .ci/scripts/run-pipeline.sh build test
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -eq 0 ]; then
  set -- build test release
fi

echo "############################################################"
echo "# Pet Adoption Platform pipeline"
echo "# PET_APP_ENV=${PET_APP_ENV:-demo}  stages: $*"
echo "############################################################"

for stage in "$@"; do
  case "$stage" in
    build)
      sh "$SCRIPT_DIR/stage-build.sh"
      ;;
    test)
      sh "$SCRIPT_DIR/stage-test.sh" "${PET_TEST_KIND:-all}"
      ;;
    release)
      sh "$SCRIPT_DIR/stage-release.sh"
      ;;
    *)
      echo "ERROR: unknown stage '$stage' (expected build|test|release)" >&2
      exit 1
      ;;
  esac
done

echo "==> pipeline completed: $*"
