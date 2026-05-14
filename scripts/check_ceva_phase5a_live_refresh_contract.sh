#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_ACCEPTED_LOG="${ROOT_DIR}/logs/phase4c6_20260513_230221/run.log"
PROOF_LOG="${PHASE5A_LOG_PATH:-${PHASE4G_LOG_PATH:-}}"
BUNDLE_DIR="${PHASE5A_BUNDLE_DIR:-${PHASE4H_BUNDLE_DIR:-}}"
PHASE3_GATE="${ROOT_DIR}/scripts/check_ceva_phase3_completion_gate.sh"
P4GJ_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4g_to_j_completion_contract.sh"
P4G_RUNNER="${ROOT_DIR}/scripts/run_ceva_phase4g_service_managed_smoke.sh"
P4H_BUNDLE_COLLECTOR="${ROOT_DIR}/scripts/collect_ceva_phase4h_observability_bundle.sh"
COMPLETION_DOC="${ROOT_DIR}/docs/bringup/ceva_bt52_phase4_g_to_j_completion_20260514.md"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing Phase5-A input: $path" >&2
    exit 1
  fi
}

require_dir() {
  local path="$1"

  if [[ ! -d "$path" ]]; then
    echo "FAIL: missing Phase5-A directory input: $path" >&2
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

require_absent_regex() {
  local pattern="$1"
  local file="$2"
  local matches

  matches="$(grep -Ein "$pattern" "$file" | grep -Ev ': MISSING|FAIL/WARN|Searching for panic/error strings|No executable has been specified|^.*\[WARN\].*SKIP_DDR_INIT' || true)"
  if [[ -n "$matches" ]]; then
    echo "FAIL: unexpected Phase5-A failure evidence in $file" >&2
    echo "$matches" >&2
    exit 1
  fi
}

if [[ -z "$PROOF_LOG" ]]; then
  echo "FAIL: PHASE5A_LOG_PATH is required for Phase5-A live refresh validation" >&2
  exit 1
fi

if [[ -z "$BUNDLE_DIR" ]]; then
  echo "FAIL: PHASE5A_BUNDLE_DIR is required for Phase5-A live refresh validation" >&2
  exit 1
fi

require_file "$PROOF_LOG"
require_dir "$BUNDLE_DIR"
require_file "$PHASE3_GATE"
require_file "$P4GJ_CHECKER"
require_file "$P4G_RUNNER"
require_file "$P4H_BUNDLE_COLLECTOR"
require_file "$COMPLETION_DOC"
require_file "${BUNDLE_DIR}/SUMMARY.txt"
require_file "${BUNDLE_DIR}/proof_run.log"
require_file "${BUNDLE_DIR}/phase4g_check.txt"
require_file "${BUNDLE_DIR}/phase4d_to_f_check.txt"
require_file "${BUNDLE_DIR}/phase4c_check.txt"
require_file "${BUNDLE_DIR}/ceva_runtime_launch_manifest.env"
require_file "${BUNDLE_DIR}/chipyard-zcu104-fedora.dts"

if [[ "${PHASE5A_ALLOW_ACCEPTED_C6:-0}" != "1" ]]; then
  if [[ "$(readlink -f "$PROOF_LOG")" == "$(readlink -f "$DEFAULT_ACCEPTED_LOG")" ]]; then
    echo "FAIL: Phase5-A requires a fresh live run log, not the accepted Phase4-C6 proof log" >&2
    exit 1
  fi
fi

bash "$PHASE3_GATE" --require-pass >/dev/null
PHASE4C6_LOG_PATH="$PROOF_LOG" bash "$P4GJ_CHECKER" >/dev/null

require_text "PHASE4G_SERVICE_MANAGED_RUN_START" "$PROOF_LOG"
require_text "PHASE4G_SERVICE_MANAGED_RUN_DONE" "$PROOF_LOG"
require_text "CEVA BT5.2 registered as hci0" "$PROOF_LOG"
require_text "BT core running (CLKN 5/5 OK)" "$PROOF_LOG"
require_text "ceva_bt_open: OK" "$PROOF_LOG"
require_text "PHASE25_USER_CMD_0c03_POLL_READY" "$PROOF_LOG"
require_text "PHASE25_USER_CMD_1001_POLL_READY" "$PROOF_LOG"
require_text "PHASE25_USER_HCI_RESET_PASS" "$PROOF_LOG"
require_text "PHASE25_USER_HCI_RLV_PASS" "$PROOF_LOG"
require_text "PHASE25_USER_SMOKE_PASS" "$PROOF_LOG"
require_text "CEVA_PHASE25_SELFTEST_PASS: PASS" "$PROOF_LOG"
require_text "[boot-owner] claimed=yes" "$PROOF_LOG"
require_absent_regex 'Kernel panic|Oops|BUG:|Unable to handle|Segmentation fault|CEVA_PHASE25_.*_FAIL|PHASE25_USER_.*_FAIL' "$PROOF_LOG"

require_text "P4H_OBSERVABILITY_BUNDLE=PASS" "${BUNDLE_DIR}/SUMMARY.txt"
require_text "PROOF_LOG_SHA256=" "${BUNDLE_DIR}/SUMMARY.txt"
require_text "MANIFEST_SHA256=" "${BUNDLE_DIR}/SUMMARY.txt"
require_text "DTS_SHA256=" "${BUNDLE_DIR}/SUMMARY.txt"
require_text "P4G_FEDORA_BLUEZ_SERVICE_INTEGRATION=PASS" "${BUNDLE_DIR}/phase4g_check.txt"
require_text "P4D_TO_F_HARDENING_CONTRACT=PASS" "${BUNDLE_DIR}/phase4d_to_f_check.txt"
require_text "P4C_MEMORY_OWNERSHIP_CONTRACT=PASS" "${BUNDLE_DIR}/phase4c_check.txt"

if ! cmp -s "$PROOF_LOG" "${BUNDLE_DIR}/proof_run.log"; then
  echo "FAIL: Phase5-A bundle proof_run.log does not match PHASE5A_LOG_PATH" >&2
  exit 1
fi

require_text "No RF, discovery, scan, pair, connect" "$COMPLETION_DOC"
require_text "Do not describe this package as scan/pair/connect success" "$COMPLETION_DOC"

echo "CEVA Phase5-A live proof refresh contract"
echo "proof_log=${PROOF_LOG}"
echo "bundle_dir=${BUNDLE_DIR}"
echo "p4g_runner=${P4G_RUNNER}"
echo "p4h_bundle_collector=${P4H_BUNDLE_COLLECTOR}"
echo "P5A_PHASE4_BASELINE_PRECHECK=PASS"
echo "P5A_LIVE_BOARD_PROOF_REFRESH=PASS"
echo "P5A_OBSERVABILITY_BUNDLE_REFRESH=PASS"
echo "P5A_NO_RF_SCAN_PAIR_CONNECT_CLAIM=PASS"
echo "P5A_LIVE_REFRESH_CONTRACT=PASS"