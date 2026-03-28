#!/usr/bin/env bash
set -euo pipefail

FW=${1:-/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin}
ELF=${2:-${FW%.bin}.elf}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/runtime_0200_instruction_evidence.tcl"
RUNNER="$SCRIPT_DIR/run_xsdb_single_server.sh"
SUMMARIZER="$SCRIPT_DIR/summarize_0200_instruction_evidence.py"
OBJDUMP=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-objdump
ADDR2LINE=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-addr2line
TS=$(date +%Y%m%d_%H%M%S)
LOG="$SCRIPT_DIR/../logs/runtime_0200_instruction_evidence_${TS}.log"
SUMMARY="$SCRIPT_DIR/../logs/runtime_0200_instruction_evidence_${TS}.summary.txt"

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

{
  echo
  echo "==== payload file window raw ===="
  od -An -tx4 -j $((0x21c0)) -N $((0x80)) "$FW"

  if python3 -c 'import capstone' >/dev/null 2>&1; then
    echo
    echo "==== mirrored target bytes as aarch64 0x1c0..0x240 ===="
    FW_PATH="$FW" python3 - <<'PY'
from capstone import *
import os
from pathlib import Path

fw = Path(os.environ["FW_PATH"]).read_bytes()
code = fw[0x21C0:0x2240]
md = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)
md.skipdata = True
for insn in md.disasm(code, 0x1C0):
    print(f"0x{insn.address:03x}:\t{insn.bytes.hex()}\t{insn.mnemonic}\t{insn.op_str}")
PY
  fi

  if [[ -f "$ELF" && -x "$OBJDUMP" ]]; then
    echo
    echo "==== fw_payload disassembly 0x800021c0..0x80002240 ===="
    "$OBJDUMP" -d "$ELF" --start-address=0x800021c0 --stop-address=0x80002240
  fi

  if [[ -f "$ELF" && -x "$ADDR2LINE" ]]; then
    echo
    echo "==== addr2line focus 0x800021fc/2200/2204/2208 ===="
    "$ADDR2LINE" -f -C -e "$ELF" 0x800021fc 0x80002200 0x80002204 0x80002208
  fi
} >> "$LOG"

if [[ -f "$SUMMARIZER" ]]; then
  python3 "$SUMMARIZER" "$LOG" > "$SUMMARY" || true
fi

echo "LOG:$LOG"
echo "SUMMARY:$SUMMARY"
grep -aE '^(OFFSET_RELATION|WINDOW_MATCH_COUNT|WINDOW_FULL_MATCH|PRE_PARK_PC|PRE_PARK_STATE_REASON|PARK_RECOVERY_USED|PARK_STATE_REASON|PARK_PC|PARK_CPSR|STEP[0-5]_(STATE_REASON|PC|CPSR|R0|SP|NEIGHBOR_WORDS))' "$LOG" || true
[[ -f "$SUMMARY" ]] && cat "$SUMMARY"
