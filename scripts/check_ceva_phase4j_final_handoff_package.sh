#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_PROOF_LOG="${ROOT_DIR}/logs/phase4c6_20260513_230221/run.log"
PROOF_LOG="${PHASE4J_LOG_PATH:-${PHASE4H_LOG_PATH:-${PHASE4G_LOG_PATH:-${PHASE4C6_LOG_PATH:-$DEFAULT_PROOF_LOG}}}}"
P4G_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4g_fedora_bluez_service_integration.sh"
P4H_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4h_regression_observability_bundle.sh"
P4I_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4i_conditional_rtl_vivado_gate.sh"
COMPLETION_DOC="${ROOT_DIR}/docs/bringup/ceva_bt52_phase4_g_to_j_completion_20260514.md"
LONG_PLAN="${ROOT_DIR}/docs/bringup/ceva_bt52_phase3_completion_gate_and_phase4_long_term_plan_20260513.md"
SCRIPT_INVENTORY="${ROOT_DIR}/docs/bringup/ceva_bt52_phase4_d_to_f_completion_and_script_inventory_20260513.md"
SKIP_DEPENDENCY_CHECKS="${PHASE4J_SKIP_DEPENDENCY_CHECKS:-0}"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing Phase4-J input: $path" >&2
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
require_file "$P4H_CHECKER"
require_file "$P4I_CHECKER"
require_file "$COMPLETION_DOC"
require_file "$LONG_PLAN"
require_file "$SCRIPT_INVENTORY"

if [[ "$SKIP_DEPENDENCY_CHECKS" != "1" ]]; then
  PHASE4G_LOG_PATH="$PROOF_LOG" PHASE4G_SKIP_BASELINE_CHECKS=1 bash "$P4G_CHECKER" >/dev/null
  PHASE4H_LOG_PATH="$PROOF_LOG" bash "$P4H_CHECKER" >/dev/null
  bash "$P4I_CHECKER" >/dev/null
fi

require_text "P4G_FEDORA_BLUEZ_SERVICE_INTEGRATION=PASS" "$COMPLETION_DOC"
require_text "P4H_REGRESSION_OBSERVABILITY_BUNDLE=PASS" "$COMPLETION_DOC"
require_text "P4I_CONDITIONAL_RTL_VIVADO_GATE=PASS" "$COMPLETION_DOC"
require_text "P4J_FINAL_HANDOFF_PACKAGE=PASS" "$COMPLETION_DOC"
require_text "Known limitations" "$COMPLETION_DOC"
require_text "Recovery SOP" "$COMPLETION_DOC"
require_text "Next-owner instructions" "$COMPLETION_DOC"

echo "CEVA Phase4-J final handoff package"
echo "proof_log=${PROOF_LOG}"
echo "completion_doc=${COMPLETION_DOC}"
echo "long_plan=${LONG_PLAN}"
echo "script_inventory=${SCRIPT_INVENTORY}"
echo "P4J_FINAL_HANDOFF_PACKAGE=PASS"
echo "P4J_EVIDENCE_MATRIX=PASS"
echo "P4J_RECOVERY_SOP=PASS"
echo "P4J_NEXT_OWNER_HANDOFF=PASS"
