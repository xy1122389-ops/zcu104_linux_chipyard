#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <fw_payload-flat-path>" >&2
  exit 1
fi

PAYLOAD_PATH=$(realpath "$1")
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/runtime_signature_probe.tcl"
RUNNER="$SCRIPT_DIR/run_xsdb_single_server.sh"

if [[ ! -f "$PAYLOAD_PATH" ]]; then
  echo "Error: payload not found: $PAYLOAD_PATH" >&2
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

EXP_PC="pc: 0000000000000200"
EXP_SP="sp: d0860ba2214002a7"
EXP_W_01E0="97BA47E7"
EXP_W_01E4="0007B023"
EXP_W_0200="008A3783"
EXP_W_0204="B883CF95"

TS=$(date +%Y%m%d_%H%M%S)
LOG="$SCRIPT_DIR/../logs/runtime_signature_check_${TS}.log"
"$RUNNER" "$TCL_SCRIPT" "$PAYLOAD_PATH" > "$LOG" 2>&1 || true

pc=$(grep -a -m1 '^SIG_PC=' "$LOG" | cut -d= -f2- | tr -d '\r' || true)
sp=$(grep -a -m1 '^SIG_SP=' "$LOG" | cut -d= -f2- | tr -d '\r' || true)
w1e0=$(grep -a -m1 '^SIG_W_01E0=' "$LOG" | cut -d= -f2- | tr -d '\r' || true)
w1e4=$(grep -a -m1 '^SIG_W_01E4=' "$LOG" | cut -d= -f2- | tr -d '\r' || true)
w200=$(grep -a -m1 '^SIG_W_0200=' "$LOG" | cut -d= -f2- | tr -d '\r' || true)
w204=$(grep -a -m1 '^SIG_W_0204=' "$LOG" | cut -d= -f2- | tr -d '\r' || true)

echo "LOG:$LOG"
echo "SIG_PC:$pc"
echo "SIG_SP:$sp"
echo "SIG_W_01E0:$w1e0"
echo "SIG_W_01E4:$w1e4"
echo "SIG_W_0200:$w200"
echo "SIG_W_0204:$w204"

if [[ "$pc" == "$EXP_PC" && "$sp" == "$EXP_SP" && "$w1e0" == "$EXP_W_01E0" && "$w1e4" == "$EXP_W_01E4" && "$w200" == "$EXP_W_0200" && "$w204" == "$EXP_W_0204" ]]; then
  echo "RUNTIME_SIGNATURE:PASS"
  exit 0
fi

echo "RUNTIME_SIGNATURE:FAIL"
exit 10
