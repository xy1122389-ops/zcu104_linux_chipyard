#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_PROOF_LOG="${ROOT_DIR}/logs/phase4c6_20260513_230221/run.log"
PROOF_LOG="${PHASE4J_LOG_PATH:-${PHASE4H_LOG_PATH:-${PHASE4G_LOG_PATH:-${PHASE4C6_LOG_PATH:-$DEFAULT_PROOF_LOG}}}}"
P4B_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4b_runtime_launch_contract.sh"
P4C_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4c_memory_ownership_contract.sh"
P4DF_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4d_to_f_hardening_contract.sh"
P4G_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4g_fedora_bluez_service_integration.sh"
P4H_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4h_regression_observability_bundle.sh"
P4I_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4i_conditional_rtl_vivado_gate.sh"
P4J_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4j_final_handoff_package.sh"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing Phase4 G-J completion input: $path" >&2
    exit 1
  fi
}

require_file "$PROOF_LOG"
require_file "$P4B_CHECKER"
require_file "$P4C_CHECKER"
require_file "$P4DF_CHECKER"
require_file "$P4G_CHECKER"
require_file "$P4H_CHECKER"
require_file "$P4I_CHECKER"
require_file "$P4J_CHECKER"

bash "$P4B_CHECKER" >/dev/null
PHASE4C6_LOG_PATH="$PROOF_LOG" bash "$P4C_CHECKER" >/dev/null
PHASE4C6_LOG_PATH="$PROOF_LOG" bash "$P4DF_CHECKER" >/dev/null
PHASE4G_LOG_PATH="$PROOF_LOG" PHASE4G_SKIP_BASELINE_CHECKS=1 bash "$P4G_CHECKER" >/dev/null
PHASE4H_LOG_PATH="$PROOF_LOG" bash "$P4H_CHECKER" >/dev/null
bash "$P4I_CHECKER" >/dev/null
PHASE4J_LOG_PATH="$PROOF_LOG" PHASE4J_SKIP_DEPENDENCY_CHECKS=1 bash "$P4J_CHECKER" >/dev/null

echo "CEVA Phase4-G..J completion contract"
echo "proof_log=${PROOF_LOG}"
echo "P4G_FEDORA_BLUEZ_SERVICE_INTEGRATION=PASS"
echo "P4H_REGRESSION_OBSERVABILITY_BUNDLE=PASS"
echo "P4I_CONDITIONAL_RTL_VIVADO_GATE=PASS"
echo "P4J_FINAL_HANDOFF_PACKAGE=PASS"
echo "P4G_TO_J_COMPLETION_CONTRACT=PASS"
