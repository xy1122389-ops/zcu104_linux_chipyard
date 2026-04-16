#!/usr/bin/env bash
# test_old_bitstream.sh — Quick test: program OLD (working) bitstream + try J-Link
#
# If J-Link connects with old bitstream but NOT with new:
#   → new bitstream has a design/Verilog bug
# If J-Link fails with BOTH:
#   → board/wiring/hardware issue
#
# Usage: bash scripts/test_old_bitstream.sh

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OBJ_DIR="${FPGA_DIR}/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/obj"

# The old working bitstream (pre-2MB MMIO window expansion)
OLD_BIT="${OBJ_DIR}/ZCU104FPGATestHarness.bit.bak.pre_2mb_20260414_092855"
PSU_INIT="${OBJ_DIR}/ip/zcu104ps/psu_init.tcl"

JLINK_GDB_SERVER='C:\Program Files\SEGGER\JLink\JLinkGDBServerCL.exe'
JLINK_HOST="${JLINK_HOST:-172.19.128.1}"
JLINK_PORT="${JLINK_PORT:-2331}"

echo "============================================"
echo "  OLD BITSTREAM TEST"
echo "============================================"

if [[ ! -f "$OLD_BIT" ]]; then
  echo "ERROR: Old bitstream not found: $OLD_BIT"
  echo "Available backups:"
  ls -la "${OBJ_DIR}/"*.bit* 2>/dev/null
  exit 1
fi

echo "Old bitstream: $OLD_BIT"
echo "Size: $(stat -c %s "$OLD_BIT") bytes"
echo "Date: $(stat -c '%y' "$OLD_BIT")"
echo ""

# Phase 1: Program old bitstream
echo "=== Step 1: Programming old bitstream ==="
bash "${SCRIPT_DIR}/run_ps_ddr_init.sh" --bit "$OLD_BIT" --psu-init "$PSU_INIT" 2>&1
echo ""
echo "Waiting 5s for PL stabilization..."
sleep 5

# Phase 2: Kill hw_server, try J-Link
echo "=== Step 2: J-Link connection test ==="
powershell.exe -NoProfile -Command 'Stop-Process -Name hw_server -ErrorAction SilentlyContinue' 2>/dev/null || true
powershell.exe -NoProfile -Command 'Stop-Process -Name JLinkGDBServerCL,JLink -ErrorAction SilentlyContinue' 2>/dev/null || true
sleep 3

echo "Starting J-Link GDB Server (-noir) ..."
powershell.exe -NoProfile -Command "Start-Process -FilePath '${JLINK_GDB_SERVER}' \
  -ArgumentList '-select','USB','-device','RISC-V','-endian','little',\
  '-if','JTAG','-speed','1000','-noir','-localhostonly','0','-port','${JLINK_PORT}' \
  -WindowStyle Normal" 2>/dev/null

echo "Waiting 8s for J-Link to initialize..."
sleep 8

if nc -z -w 3 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
  echo ""
  echo "============================================"
  echo "  RESULT: J-Link CONNECTS with old bitstream!"
  echo "  → NEW bitstream has a design bug."
  echo "  → Compare Verilog changes between versions."
  echo "============================================"
else
  echo ""
  echo "============================================"
  echo "  RESULT: J-Link ALSO FAILS with old bitstream."
  echo "  → Board/wiring/hardware issue."
  echo "  → Try: full power cycle (OFF 10s ON)"
  echo "  → Check PMOD0 wiring"
  echo "  → Check J-Link USB connection"
  echo "============================================"
fi

# Cleanup: stop J-Link
powershell.exe -NoProfile -Command 'Stop-Process -Name JLinkGDBServerCL -ErrorAction SilentlyContinue' 2>/dev/null || true
