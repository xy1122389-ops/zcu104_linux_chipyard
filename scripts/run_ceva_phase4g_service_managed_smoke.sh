#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT_DIR}/run_phase2_ceva_bt_linux.sh"
JLINK_PRECHECK="${ROOT_DIR}/scripts/jlink_recover_and_precheck.sh"

RUN_TAG="${PHASE4G_RUN_TAG:-phase4g_$(date +%Y%m%d_%H%M%S)}"
LOG_DIR="${PHASE4G_LOG_DIR:-${ROOT_DIR}/logs/${RUN_TAG}}"
LOG_PATH="${PHASE4G_LOG_PATH:-${LOG_DIR}/run.log}"
JLINK_HOST="${JLINK_HOST:-127.0.0.1}"
JLINK_PORT="${JLINK_PORT:-3333}"
KERNEL_RUN_SECS="${PHASE4G_KERNEL_RUN_SECS:-180}"
SKIP_DDR_INIT="${PHASE4G_SKIP_DDR_INIT:-1}"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing Phase4-G run input: $path" >&2
    exit 1
  fi
}

require_file "$RUNNER"
require_file "$JLINK_PRECHECK"

mkdir -p "$LOG_DIR"

{
  echo "CEVA Phase4-G service-managed smoke"
  echo "run_tag=${RUN_TAG}"
  echo "jlink=${JLINK_HOST}:${JLINK_PORT}"
  echo "kernel_run_secs=${KERNEL_RUN_SECS}"
  echo "skip_ddr_init=${SKIP_DDR_INIT}"
  echo "workflow=JLink-precheck -> Linux/Fedora bringup -> hci0 Reset/RLV proof capture"
  echo "PHASE4G_SERVICE_MANAGED_RUN_START"

  JLINK_HOST="$JLINK_HOST" \
  JLINK_PORT="$JLINK_PORT" \
    bash "$JLINK_PRECHECK"

  SKIP_DDR_INIT="$SKIP_DDR_INIT" \
  JLINK_HOST="$JLINK_HOST" \
  JLINK_PORT="$JLINK_PORT" \
  KERNEL_RUN_SECS="$KERNEL_RUN_SECS" \
  RUN_TAG="$RUN_TAG" \
    bash "$RUNNER"

  echo "PHASE4G_SERVICE_MANAGED_RUN_DONE"
} 2>&1 | tee "$LOG_PATH"

echo "PHASE4G_LOG_PATH=${LOG_PATH}"
