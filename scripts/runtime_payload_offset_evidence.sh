#!/usr/bin/env bash
set -euo pipefail

FW=${1:-/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/runtime_payload_offset_evidence.tcl"
RUNNER="$SCRIPT_DIR/run_xsdb_single_server.sh"
SUMMARIZER="$SCRIPT_DIR/summarize_payload_offset_evidence.py"
TS=$(date +%Y%m%d_%H%M%S)
LOG="$SCRIPT_DIR/../logs/runtime_payload_offset_evidence_${TS}.log"
SUMMARY="$SCRIPT_DIR/../logs/runtime_payload_offset_evidence_${TS}.summary.txt"

if [[ ! -f "$FW" ]]; then
  echo "Error: payload not found: $FW" >&2
  exit 2
fi

if [[ ! -f "$TCL_SCRIPT" ]]; then
  echo "Error: missing TCL script: $TCL_SCRIPT" >&2
  exit 3
fi

if [[ ! -x "$RUNNER" ]]; then
  echo "Error: missing XSDB runner: $RUNNER" >&2
  exit 4
fi

"$RUNNER" "$TCL_SCRIPT" "$FW" > "$LOG" 2>&1 || true
if [[ -f "$SUMMARIZER" ]]; then
  python3 "$SUMMARIZER" "$LOG" > "$SUMMARY" || true
fi
echo "LOG:$LOG"
echo "SUMMARY:$SUMMARY"
grep -aE '^(WINDOW_BASE|WINDOW_SUMMARY|MATCH_SAME_OFFSET|MATCH_PLUS_2000|FULL_MATCH_SAME_OFFSET|FULL_MATCH_PLUS_2000|PARTIAL_PLUS_WINDOW_DETAIL|FULL_MATCH_PLUS_2000_BASES|PARTIAL_MATCH_PLUS_2000_BASES|NO_MATCH_PLUS_2000_BASES|FULL_MATCH_SAME_OFFSET_BASES|FULL_MATCH_PLUS_2000_RUNS|FULL_MATCH_SELF_RUNS|LAST_FULL_PLUS_BASE|FIRST_FULL_SELF_BASE|TRANSITION_INTERVAL|FULL_PLUS_CONTIGUOUS_FROM_ZERO|IS_PLUS_2000_GLOBAL_ACROSS_SAMPLES|PLUS_2000_MATCH_SCOPE|LIKELY_ALIAS_REMAP_WINDOW)' "$LOG" || true
[[ -f "$SUMMARY" ]] && cat "$SUMMARY"
