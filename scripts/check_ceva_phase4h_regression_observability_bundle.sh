#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_PROOF_LOG="${ROOT_DIR}/logs/phase4c6_20260513_230221/run.log"
PROOF_LOG="${PHASE4H_LOG_PATH:-${PHASE4G_LOG_PATH:-${PHASE4C6_LOG_PATH:-$DEFAULT_PROOF_LOG}}}"
P4G_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4g_fedora_bluez_service_integration.sh"
BUNDLE_COLLECTOR="${ROOT_DIR}/scripts/collect_ceva_phase4h_observability_bundle.sh"
CAPTURE_GDB="${ROOT_DIR}/scripts/linux_boot_phase2_capture.gdb"
COMPLETION_DOC="${ROOT_DIR}/docs/bringup/ceva_bt52_phase4_g_to_j_completion_20260514.md"
TMP_BUNDLE="$(mktemp -d /tmp/ceva_phase4h_bundle_check.XXXXXX)"
trap 'rm -rf "$TMP_BUNDLE"' EXIT

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing Phase4-H input: $path" >&2
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

require_file "$PROOF_LOG"
require_file "$P4G_CHECKER"
require_file "$BUNDLE_COLLECTOR"
require_file "$CAPTURE_GDB"
require_file "$COMPLETION_DOC"

PHASE4G_LOG_PATH="$PROOF_LOG" PHASE4G_SKIP_BASELINE_CHECKS=1 bash "$P4G_CHECKER" >/dev/null

require_text "/tmp/phase2_klog.bin" "$CAPTURE_GDB"
require_text "/tmp/phase2_phase25_evidence.bin" "$CAPTURE_GDB"
require_text "CEVA_PHASE25" "$CAPTURE_GDB"
require_text "CHECK 4: hci0 registration" "$CAPTURE_GDB"
require_text "PHASE25_MARK_HCI_RESET_PASS" "$CAPTURE_GDB"
require_text "PHASE25_MARK_READ_LOCAL_VERSION_PASS" "$CAPTURE_GDB"

PHASE4G_LOG_PATH="$PROOF_LOG" PHASE4G_SKIP_BASELINE_CHECKS=1 bash "$BUNDLE_COLLECTOR" "$TMP_BUNDLE" >/dev/null
require_text "P4H_OBSERVABILITY_BUNDLE=PASS" "${TMP_BUNDLE}/SUMMARY.txt"
require_text "PROOF_LOG_SHA256=" "${TMP_BUNDLE}/SUMMARY.txt"
require_text "MANIFEST_SHA256=" "${TMP_BUNDLE}/SUMMARY.txt"
require_text "DTS_SHA256=" "${TMP_BUNDLE}/SUMMARY.txt"
require_text "P4H_REGRESSION_OBSERVABILITY_BUNDLE=PASS" "$COMPLETION_DOC"

echo "CEVA Phase4-H regression and observability"
echo "proof_log=${PROOF_LOG}"
echo "bundle_collector=${BUNDLE_COLLECTOR}"
echo "capture_gdb=${CAPTURE_GDB}"
echo "P4H_REGRESSION_OBSERVABILITY_BUNDLE=PASS"
echo "P4H_ARTIFACT_BUNDLE_COLLECTOR=PASS"
echo "P4H_FAILURE_TRIAGE_SURFACE=PASS"
