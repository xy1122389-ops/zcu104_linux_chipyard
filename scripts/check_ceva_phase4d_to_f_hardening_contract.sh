#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P4D_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4d_vendor_build_reproducibility.sh"
P4E_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4e_driver_lifecycle_hardening.sh"
P4F_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4f_interrupt_timer_power_hardening.sh"
DEFAULT_PROOF_LOG="${ROOT_DIR}/logs/phase4c6_20260513_230221/run.log"
PROOF_LOG="${PHASE4F_LOG_PATH:-${PHASE4E_LOG_PATH:-${PHASE4C6_LOG_PATH:-$DEFAULT_PROOF_LOG}}}"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing Phase4 D-F checker input: $path" >&2
    exit 1
  fi
}

require_file "$P4D_CHECKER"
require_file "$P4E_CHECKER"
require_file "$P4F_CHECKER"
require_file "$PROOF_LOG"

bash "$P4D_CHECKER" >/dev/null
PHASE4E_LOG_PATH="$PROOF_LOG" bash "$P4E_CHECKER" >/dev/null
PHASE4F_LOG_PATH="$PROOF_LOG" bash "$P4F_CHECKER" >/dev/null

echo "CEVA Phase4-D..F hardening contract"
echo "proof_log=${PROOF_LOG}"
echo "p4d_checker=${P4D_CHECKER}"
echo "p4e_checker=${P4E_CHECKER}"
echo "p4f_checker=${P4F_CHECKER}"
echo "P4D_VENDOR_BUILD_REPRODUCIBILITY=PASS"
echo "P4E_DRIVER_LIFECYCLE_HARDENING=PASS"
echo "P4F_INTERRUPT_TIMER_POWER_HARDENING=PASS"
echo "P4D_TO_F_HARDENING_CONTRACT=PASS"