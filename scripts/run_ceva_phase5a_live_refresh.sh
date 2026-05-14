#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P4G_RUNNER="${ROOT_DIR}/scripts/run_ceva_phase4g_service_managed_smoke.sh"
P4H_BUNDLE_COLLECTOR="${ROOT_DIR}/scripts/collect_ceva_phase4h_observability_bundle.sh"
P5A_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase5a_live_refresh_contract.sh"

RUN_TAG="${PHASE5A_RUN_TAG:-phase5a_$(date +%Y%m%d_%H%M%S)}"
LOG_DIR="${PHASE5A_LOG_DIR:-${ROOT_DIR}/logs/${RUN_TAG}}"
LOG_PATH="${PHASE5A_LOG_PATH:-${LOG_DIR}/run.log}"
BUNDLE_DIR="${PHASE5A_BUNDLE_DIR:-${ROOT_DIR}/reports/${RUN_TAG}_observability}"
JLINK_HOST="${JLINK_HOST:-127.0.0.1}"
JLINK_PORT="${JLINK_PORT:-3333}"
KERNEL_RUN_SECS="${PHASE5A_KERNEL_RUN_SECS:-180}"
SKIP_DDR_INIT="${PHASE5A_SKIP_DDR_INIT:-1}"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing Phase5-A run input: $path" >&2
    exit 1
  fi
}

require_file "$P4G_RUNNER"
require_file "$P4H_BUNDLE_COLLECTOR"
require_file "$P5A_CHECKER"

mkdir -p "$LOG_DIR"
mkdir -p "$BUNDLE_DIR"

echo "CEVA Phase5-A live proof refresh"
echo "run_tag=${RUN_TAG}"
echo "jlink=${JLINK_HOST}:${JLINK_PORT}"
echo "kernel_run_secs=${KERNEL_RUN_SECS}"
echo "skip_ddr_init=${SKIP_DDR_INIT}"
echo "log_path=${LOG_PATH}"
echo "bundle_dir=${BUNDLE_DIR}"
echo "PHASE5A_LIVE_REFRESH_RUN_START"

PHASE4G_RUN_TAG="$RUN_TAG" \
PHASE4G_LOG_DIR="$LOG_DIR" \
PHASE4G_LOG_PATH="$LOG_PATH" \
PHASE4G_KERNEL_RUN_SECS="$KERNEL_RUN_SECS" \
PHASE4G_SKIP_DDR_INIT="$SKIP_DDR_INIT" \
JLINK_HOST="$JLINK_HOST" \
JLINK_PORT="$JLINK_PORT" \
  bash "$P4G_RUNNER"

PHASE4G_LOG_PATH="$LOG_PATH" \
PHASE4G_SKIP_BASELINE_CHECKS=1 \
  bash "$P4H_BUNDLE_COLLECTOR" "$BUNDLE_DIR"

PHASE5A_LOG_PATH="$LOG_PATH" \
PHASE5A_BUNDLE_DIR="$BUNDLE_DIR" \
  bash "$P5A_CHECKER"

echo "PHASE5A_LOG_PATH=${LOG_PATH}"
echo "PHASE5A_BUNDLE_DIR=${BUNDLE_DIR}"
echo "PHASE5A_LIVE_REFRESH_RUN_DONE"