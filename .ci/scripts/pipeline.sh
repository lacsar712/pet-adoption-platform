#!/usr/bin/env sh
# pipeline.sh
# --------------------------------------------------------------------------
# TOTAL ENTRY (orchestration only). This script ONLY schedules the stages in
# order by delegating to run-stage.sh. It deliberately contains NO concrete
# stage commands (those live in run-stage.sh + the *.yml stage files).
#
# Run the full pipeline:            sh .ci/scripts/pipeline.sh
# Run a subset (space-separated):   PET_CI_STAGES="build test" sh .ci/scripts/pipeline.sh
#   only build:                     PET_CI_STAGES="build" sh .ci/scripts/pipeline.sh
#   only test:                      PET_CI_STAGES="test"  sh .ci/scripts/pipeline.sh
# Select test gates (passed through to run-stage.sh unchanged):
#   PET_TEST_GATES="unit"  PET_CI_STAGES="test" sh .ci/scripts/pipeline.sh
# Select environment (demo|ci|staging):
#   PET_APP_ENV=staging sh .ci/scripts/pipeline.sh
# --------------------------------------------------------------------------
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Default order: build -> test -> release
STAGES="${PET_CI_STAGES:-build test release}"

echo "########################################################"
echo "# pet-adoption pipeline"
echo "# PET_APP_ENV=${PET_APP_ENV:-ci}  stages: ${STAGES}"
echo "########################################################"

for stage in ${STAGES}; do
  echo ""
  echo "======================================================="
  echo "  PIPELINE STAGE: ${stage}"
  echo "======================================================="
  sh "${SCRIPT_DIR}/run-stage.sh" "${stage}"
done

echo ""
echo "########################################################"
echo "# pipeline finished OK (stages: ${STAGES})"
echo "########################################################"
