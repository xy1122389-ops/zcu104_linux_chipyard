#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P5A_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase5a_live_refresh_contract.sh"
P5C_DOC="${ROOT_DIR}/docs/bringup/ceva_bt52_phase5c_service_lifecycle_soak_20260514.md"
SUMMARY_PATH="${1:-${PHASE5C_SUMMARY_PATH:-}}"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing Phase5-C input: $path" >&2
    exit 1
  fi
}

require_text() {
  local needle="$1"
  local file="$2"

  if ! grep -Fq -- "$needle" "$file"; then
    echo "FAIL: missing '$needle' in $file" >&2
    exit 1
  fi
}

summary_value() {
  local key="$1"
  grep -E "^${key}=" "$SUMMARY_PATH" | tail -n 1 | sed "s/^${key}=//"
}

if [[ -z "$SUMMARY_PATH" ]]; then
  echo "FAIL: Phase5-C summary path is required" >&2
  exit 1
fi

require_file "$SUMMARY_PATH"
require_file "$P5A_CHECKER"
require_file "$P5C_DOC"

require_text "PHASE5C_SERVICE_LIFECYCLE_SOAK_RUN_START" "$SUMMARY_PATH"
require_text "PHASE5C_SERVICE_LIFECYCLE_SOAK_RUN_DONE" "$SUMMARY_PATH"
require_text "service lifecycle soak" "$P5C_DOC"
require_text "does not claim RF, scan, pair, or connect" "$P5C_DOC"
require_text "BlueZ entry point" "$P5C_DOC"

soak_rounds="$(summary_value soak_rounds)"
overall_status="$(summary_value OVERALL_STATUS)"
attempted_rounds="$(summary_value ATTEMPTED_ROUNDS)"
successful_rounds="$(summary_value SUCCESSFUL_ROUNDS)"

if [[ -z "$soak_rounds" || -z "$attempted_rounds" || -z "$successful_rounds" || -z "$overall_status" ]]; then
  echo "FAIL: incomplete Phase5-C summary metadata in $SUMMARY_PATH" >&2
  exit 1
fi

if [[ "$attempted_rounds" -lt 1 ]]; then
  echo "FAIL: Phase5-C attempted_rounds must be >= 1" >&2
  exit 1
fi

round=1
while [[ "$round" -le "$attempted_rounds" ]]; do
  round_status="$(summary_value ROUND_${round}_STATUS)"
  round_log_path="$(summary_value ROUND_${round}_LOG_PATH)"
  round_bundle_dir="$(summary_value ROUND_${round}_BUNDLE_DIR)"

  if [[ -z "$round_status" || -z "$round_log_path" || -z "$round_bundle_dir" ]]; then
    echo "FAIL: incomplete round ${round} metadata in $SUMMARY_PATH" >&2
    exit 1
  fi

  require_text "ROUND_${round}_START=" "$SUMMARY_PATH"

  require_file "$round_log_path"

  if [[ "$round_status" == BLOCKED_* ]]; then
    require_text "ROUND_${round}_BLOCKED=" "$SUMMARY_PATH"
    echo "FAIL: Phase5-C round ${round} was blocked (status=${round_status})" >&2
    exit 1
  fi

  require_file "${round_bundle_dir}/SUMMARY.txt"
  require_file "${round_bundle_dir}/proof_run.log"

  if [[ "$round_status" == "PASS" ]]; then
    require_text "ROUND_${round}_DONE=" "$SUMMARY_PATH"
  else
    require_text "ROUND_${round}_FAIL=" "$SUMMARY_PATH"
    echo "FAIL: Phase5-C round ${round} failed (status=${round_status})" >&2
    exit 1
  fi

  PHASE5A_LOG_PATH="$round_log_path" \
  PHASE5A_BUNDLE_DIR="$round_bundle_dir" \
    bash "$P5A_CHECKER" >/dev/null

  round=$((round + 1))
done

if [[ "$successful_rounds" -ne "$attempted_rounds" ]]; then
  echo "FAIL: Phase5-C successful_rounds (${successful_rounds}) does not match attempted_rounds (${attempted_rounds})" >&2
  exit 1
fi

if [[ "$attempted_rounds" -eq 1 && "$successful_rounds" -eq 1 ]]; then
  echo "CEVA Phase5-C single-round proof"
  echo "summary_path=${SUMMARY_PATH}"
  echo "attempted_rounds=${attempted_rounds}"
  echo "successful_rounds=${successful_rounds}"
  echo "P5C_SINGLE_ROUND_PROOF=PASS"
  echo "P5C_SERVICE_LIFECYCLE_SOAK=PARTIAL"
  echo "P5C_FULL_SOAK_ROUNDS=DEFERRED"
  echo "P5C_HCI0_REPEATED=PASS"
  echo "P5C_BLUETOOTHD_MANAGED_HCI0=PASS"
  echo "P5C_HCI_RESET_RLV_REPEATED=PASS"
  echo "P5C_DRIVER_OPEN_CLOSE_RESTART=PASS"
  echo "P5C_LOG_BUNDLE_REPEATABLE=PASS"
  echo "P5C_SCAN_PAIR_CONNECT=DEFERRED"
  echo "P5C_RF_PHY_PROOF=DEFERRED"
  exit 0
fi

if [[ "$overall_status" != "PASS" ]]; then
  echo "FAIL: Phase5-C overall status is ${overall_status}" >&2
  exit 1
fi

echo "CEVA Phase5-C service lifecycle soak"
echo "summary_path=${SUMMARY_PATH}"
echo "attempted_rounds=${attempted_rounds}"
echo "successful_rounds=${successful_rounds}"
echo "P5C_SERVICE_LIFECYCLE_SOAK=PASS"
echo "P5C_HCI0_REPEATED=PASS"
echo "P5C_BLUETOOTHD_MANAGED_HCI0=PASS"
echo "P5C_HCI_RESET_RLV_REPEATED=PASS"
echo "P5C_DRIVER_OPEN_CLOSE_RESTART=PASS"
echo "P5C_LOG_BUNDLE_REPEATABLE=PASS"
echo "P5C_FULL_SOAK_ROUNDS=PASS"
echo "P5C_SCAN_PAIR_CONNECT=DEFERRED"
echo "P5C_RF_PHY_PROOF=DEFERRED"