#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P5A_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase5a_live_refresh_contract.sh"
P5B_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase5b_single_status_surface.sh"
P5_DOC="${ROOT_DIR}/docs/bringup/ceva_bt52_phase5_live_refresh_and_status_surface_20260514.md"

PROOF_LOG="${PHASE5_LOG_PATH:-${PHASE5A_LOG_PATH:-${PHASE4G_LOG_PATH:-}}}"
BUNDLE_DIR="${PHASE5_BUNDLE_DIR:-${PHASE5A_BUNDLE_DIR:-${PHASE4H_BUNDLE_DIR:-}}}"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing Phase5 current contract input: $path" >&2
    exit 1
  fi
}

require_file "$P5A_CHECKER"
require_file "$P5B_CHECKER"
require_file "$P5_DOC"

if [[ -z "$PROOF_LOG" ]]; then
  echo "FAIL: PHASE5_LOG_PATH or PHASE5A_LOG_PATH is required for the Phase5 current contract" >&2
  exit 1
fi

if [[ -z "$BUNDLE_DIR" ]]; then
  echo "FAIL: PHASE5_BUNDLE_DIR or PHASE5A_BUNDLE_DIR is required for the Phase5 current contract" >&2
  exit 1
fi

PHASE5A_LOG_PATH="$PROOF_LOG" \
PHASE5A_BUNDLE_DIR="$BUNDLE_DIR" \
  bash "$P5A_CHECKER" >/dev/null

bash "$P5B_CHECKER" >/dev/null

echo "CEVA Phase5 current contract"
echo "proof_log=${PROOF_LOG}"
echo "bundle_dir=${BUNDLE_DIR}"
echo "current_stage=P5A_COMPLETE_P5B_STATUS_SURFACE_READY"
echo "next_stage=P5C_SERVICE_LIFECYCLE_SOAK"
echo "P5A_LIVE_REFRESH_CONTRACT=PASS"
echo "P5B_SINGLE_STATUS_SURFACE=PASS"
echo "P5_NO_RF_SCAN_PAIR_CONNECT_CERTIFICATION_CLAIM=PASS"
echo "P5_CURRENT_CONTRACT=PASS"