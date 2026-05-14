#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P5A_RUNNER="${ROOT_DIR}/scripts/run_ceva_phase5a_live_refresh.sh"
P5A_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase5a_live_refresh_contract.sh"
P5_CURRENT_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase5_current_contract.sh"
P5_DOC="${ROOT_DIR}/docs/bringup/ceva_bt52_phase5_live_refresh_and_status_surface_20260514.md"
P4GJ_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4g_to_j_completion_contract.sh"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing Phase5-B status surface input: $path" >&2
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

require_file "$P5A_RUNNER"
require_file "$P5A_CHECKER"
require_file "$P5_CURRENT_CHECKER"
require_file "$P5_DOC"
require_file "$P4GJ_CHECKER"

require_text "P5A_LIVE_REFRESH_CONTRACT=PASS" "$P5A_CHECKER"
require_text "P5A_LIVE_REFRESH_CONTRACT=PASS" "$P5_CURRENT_CHECKER"
require_text "P5B_SINGLE_STATUS_SURFACE=PASS" "$P5_CURRENT_CHECKER"
require_text "P5_CURRENT_CONTRACT=PASS" "$P5_CURRENT_CHECKER"
require_text "check_ceva_phase5_current_contract.sh" "$P5_DOC"
require_text "P5B_SINGLE_STATUS_SURFACE=PASS" "$P5_DOC"
require_text "No RF/scan/pair/connect/certification claim" "$P5_DOC"
require_text "check_ceva_phase4g_to_j_completion_contract.sh" "$P5_DOC"

echo "CEVA Phase5-B single status surface"
echo "runner=${P5A_RUNNER}"
echo "p5a_checker=${P5A_CHECKER}"
echo "current_checker=${P5_CURRENT_CHECKER}"
echo "doc=${P5_DOC}"
echo "P5B_SINGLE_STATUS_SURFACE=PASS"
echo "P5B_OUTER_ENTRY=check_ceva_phase5_current_contract.sh"