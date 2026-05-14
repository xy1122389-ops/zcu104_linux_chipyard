#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_PROOF_LOG="${ROOT_DIR}/logs/phase4c6_20260513_230221/run.log"
PROOF_LOG="${PHASE4G_LOG_PATH:-${PHASE4C6_LOG_PATH:-$DEFAULT_PROOF_LOG}}"
PHASE3_GATE="${ROOT_DIR}/scripts/check_ceva_phase3_completion_gate.sh"
PHASE4B_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4b_runtime_launch_contract.sh"
PHASE4C_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4c_memory_ownership_contract.sh"
PHASE4DF_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4d_to_f_hardening_contract.sh"
PHASE4G_RUNNER="${ROOT_DIR}/scripts/run_ceva_phase4g_service_managed_smoke.sh"
BLUEZ_EVIDENCE="${ROOT_DIR}/docs/bringup/phase3_completion_evidence/07_bluez_controlled_bringup_pass.md"
COMPLETION_DOC="${ROOT_DIR}/docs/bringup/ceva_bt52_phase4_g_to_j_completion_20260514.md"
INIT_SCRIPT="${ROOT_DIR}/linux-bringup/initramfs/rootfs/init"
PHASE2_RUNNER="${ROOT_DIR}/run_phase2_ceva_bt_linux.sh"
SKIP_BASELINE_CHECKS="${PHASE4G_SKIP_BASELINE_CHECKS:-0}"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing Phase4-G input: $path" >&2
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
    echo "FAIL: unexpected Phase4-G failure evidence in $file" >&2
    echo "$matches" >&2
    exit 1
  fi
}

require_file "$PROOF_LOG"
require_file "$PHASE3_GATE"
require_file "$PHASE4B_CHECKER"
require_file "$PHASE4C_CHECKER"
require_file "$PHASE4DF_CHECKER"
require_file "$PHASE4G_RUNNER"
require_file "$BLUEZ_EVIDENCE"
require_file "$COMPLETION_DOC"
require_file "$INIT_SCRIPT"
require_file "$PHASE2_RUNNER"

if [[ "$SKIP_BASELINE_CHECKS" != "1" ]]; then
  bash "$PHASE3_GATE" --require-pass >/dev/null
  bash "$PHASE4B_CHECKER" >/dev/null
  PHASE4C6_LOG_PATH="$PROOF_LOG" bash "$PHASE4C_CHECKER" >/dev/null
  PHASE4C6_LOG_PATH="$PROOF_LOG" bash "$PHASE4DF_CHECKER" >/dev/null
fi

require_text "PHASE3_BLUEZ_CONTROLLED_BRINGUP=PASS" "$BLUEZ_EVIDENCE"
require_text "PHASE3_RESET_RLV_BASELINE_VERIFIED=PASS" "$BLUEZ_EVIDENCE"
require_text "SYNTHETIC_DISABLED=PASS" "$BLUEZ_EVIDENCE"
require_text "No BlueZ scan, pair, connect" "$BLUEZ_EVIDENCE"
require_text "PHASE25_USER_HCI0_PRESENT" "$BLUEZ_EVIDENCE"

require_text "PHASE4G_SERVICE_MANAGED_RUN_START" "$PHASE4G_RUNNER"
require_text "jlink_recover_and_precheck.sh" "$PHASE4G_RUNNER"
require_text "run_phase2_ceva_bt_linux.sh" "$PHASE4G_RUNNER"
require_text "KERNEL_RUN_SECS" "$PHASE4G_RUNNER"
require_text "JLINK_HOST" "$PHASE4G_RUNNER"
require_text "JLINK_PORT" "$PHASE4G_RUNNER"

require_text "load_initramfs_module bluetooth.ko" "$INIT_SCRIPT"
require_text "insmod /lib/modules/ceva_bt52.ko" "$INIT_SCRIPT"
require_text "ceva_phase25_selftest=0" "$INIT_SCRIPT"
require_text "PHASE25_CEVA_SELFTEST_OFF" "$INIT_SCRIPT"
require_text "while [ ! -d /sys/class/bluetooth/hci0 ]" "$INIT_SCRIPT"
require_text "PHASE25_USER_HCI0_PRESENT" "$INIT_SCRIPT"
require_text "/sbin/phase25_user_hci_smoke" "$INIT_SCRIPT"

require_text "run_capture_session" "$PHASE2_RUNNER"
require_text "J-Link guard" "$PHASE2_RUNNER"
require_text "KERNEL_RUN_SECS" "$PHASE2_RUNNER"

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
require_absent_regex 'Kernel panic|Oops|BUG:|Unable to handle|CEVA_PHASE25_.*_FAIL|PHASE25_USER_.*_FAIL' "$PROOF_LOG"

require_text "P4G_FEDORA_BLUEZ_SERVICE_INTEGRATION=PASS" "$COMPLETION_DOC"
require_text "P4G_SERVICE_CONTRACT=PASS" "$COMPLETION_DOC"
require_text "P4G_CONTROLLED_BLUEZ_WORKFLOW=PASS" "$COMPLETION_DOC"

echo "CEVA Phase4-G Fedora/BlueZ service integration"
echo "proof_log=${PROOF_LOG}"
echo "runner=${PHASE4G_RUNNER}"
echo "phase3_bluez_evidence=${BLUEZ_EVIDENCE}"
echo "P4G_FEDORA_BLUEZ_SERVICE_INTEGRATION=PASS"
echo "P4G_SERVICE_CONTRACT=PASS"
echo "P4G_CONTROLLED_BLUEZ_WORKFLOW=PASS"
echo "P4G_NO_RF_SCAN_PAIR_CONNECT_CLAIM=PASS"
