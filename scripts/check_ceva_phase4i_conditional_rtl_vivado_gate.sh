#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPLETION_DOC="${ROOT_DIR}/docs/bringup/ceva_bt52_phase4_g_to_j_completion_20260514.md"
ENTER_PHASE4I="${PHASE4I_ENTER:-0}"
DEFECT_BRIEF="${PHASE4I_DEFECT_BRIEF:-}"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing Phase4-I input: $path" >&2
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

require_file "$COMPLETION_DOC"
require_text "P4I_CONDITIONAL_RTL_VIVADO_GATE=PASS" "$COMPLETION_DOC"

if [[ "$ENTER_PHASE4I" == "1" ]]; then
  if [[ -z "$DEFECT_BRIEF" ]]; then
    echo "FAIL: PHASE4I_ENTER=1 requires PHASE4I_DEFECT_BRIEF" >&2
    exit 1
  fi
  require_file "$DEFECT_BRIEF"
  require_text "PHASE4I_NAMED_HARDWARE_DEFECT=PASS" "$DEFECT_BRIEF"
  require_text "PHASE4I_MINIMAL_REPRO=PASS" "$DEFECT_BRIEF"
  require_text "PHASE4I_ROLLBACK_PLAN=PASS" "$DEFECT_BRIEF"
  echo "phase4i_mode=entered"
  echo "defect_brief=${DEFECT_BRIEF}"
else
  require_text "P4I_RTL_VIVADO_NOT_ENTERED=PASS" "$COMPLETION_DOC"
  echo "phase4i_mode=not_entered_no_named_hardware_defect"
fi

echo "P4I_CONDITIONAL_RTL_VIVADO_GATE=PASS"
echo "P4I_RTL_VIVADO_ENTRY_RULE=PASS"
if [[ "$ENTER_PHASE4I" != "1" ]]; then
  echo "P4I_RTL_VIVADO_NOT_ENTERED=PASS"
fi
