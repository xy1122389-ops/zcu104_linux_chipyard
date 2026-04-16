#!/usr/bin/env bash
# jlink_jtag_diag.sh — Low-level JTAG diagnostic via J-Link Commander
#
# Reads IDCODE, DTMCS, and dmstatus WITHOUT trying to halt the core.
# This tells us exactly where in the JTAG→DMI→Debug chain the failure is.
#
# Usage: bash scripts/jlink_jtag_diag.sh

set -uo pipefail

JLINK_EXE='C:\Program Files\SEGGER\JLink\JLink.exe'
JLINK_SERIAL="${JLINK_USB_SERIAL:-601012542}"

# Kill any existing J-Link processes first
echo "=== Killing existing J-Link processes ==="
powershell.exe -NoProfile -Command 'Stop-Process -Name JLinkGDBServerCL,JLink -ErrorAction SilentlyContinue' 2>/dev/null || true
sleep 2

# Create J-Link Commander script
# Strategy: connect with RISC-V device, then use mem32 to check debug module
JLINK_CMDS=$(mktemp /mnt/c/Windows/Temp/jlink_diag_XXXX.jlink 2>/dev/null || mktemp /tmp/jlink_diag_XXXX.jlink)
JLINK_CMDS_WIN=$(wslpath -w "$JLINK_CMDS" 2>/dev/null || echo "$JLINK_CMDS")

# The 'connect' command triggers JTAG chain scan + connection attempt.
# Even if it fails to halt, the output shows IDCODE, TAP info, etc.
cat > "$JLINK_CMDS" << 'CMDS'
connect
q
CMDS

echo ""
echo "=== J-Link JTAG Diagnostic ==="
echo "Serial: $JLINK_SERIAL"
echo ""
echo "--- Test 1: Connect with RISC-V device (shows chain scan) ---"

DIAG_OUTPUT=$(powershell.exe -NoProfile -Command "& '$JLINK_EXE' \
  -SelectEmuBySN $JLINK_SERIAL \
  -Device RISC-V -IF JTAG -Speed 1000 \
  -JTAGConf 0,0 \
  -ExitOnError 0 \
  -CommandFile '$JLINK_CMDS_WIN' 2>&1" 2>&1)

echo "$DIAG_OUTPUT"
echo ""
echo "=== DIAGNOSTIC ANALYSIS ==="

# Check what happened
HAS_VTREF=0
HAS_IDCODE=0
HAS_DEVICE=0
HAS_HALT_TIMEOUT=0
HAS_NO_DEVICE=0
HAS_CONNECTED=0

echo "$DIAG_OUTPUT" | grep -qi "VTref" && HAS_VTREF=1
echo "$DIAG_OUTPUT" | grep -qi "IDCODE\|Id of device" && HAS_IDCODE=1
echo "$DIAG_OUTPUT" | grep -qi "Found [0-9]\|NumDevices\|device.*found" && HAS_DEVICE=1
echo "$DIAG_OUTPUT" | grep -qi "Timeout.*halt\|halt.*timeout" && HAS_HALT_TIMEOUT=1
echo "$DIAG_OUTPUT" | grep -qi "Cannot find\|No JTAG\|No device\|scan failed" && HAS_NO_DEVICE=1
echo "$DIAG_OUTPUT" | grep -qi "Connected to\|connected successfully" && HAS_CONNECTED=1

# "Cannot connect to target" also appears after a successful chain scan when
# the TAP is visible but the core cannot be halted. Only classify as "no
# device" if chain detection never found a device.
if [[ $HAS_DEVICE -eq 1 ]]; then
  HAS_NO_DEVICE=0
fi

VTREF_VAL=$(echo "$DIAG_OUTPUT" | grep -oi "VTref=[0-9.]*V" | head -1)

echo "  VTref detected:    $([ $HAS_VTREF -eq 1 ] && echo "YES ($VTREF_VAL)" || echo "NO")"
echo "  JTAG IDCODE found: $([ $HAS_IDCODE -eq 1 ] && echo "YES ← TAP is alive" || echo "NO")"
echo "  Device found:      $([ $HAS_DEVICE -eq 1 ] && echo "YES" || echo "NO")"
echo "  Halt timeout:      $([ $HAS_HALT_TIMEOUT -eq 1 ] && echo "YES ← DMI works but halt fails" || echo "NO")"
echo "  No device:         $([ $HAS_NO_DEVICE -eq 1 ] && echo "YES ← JTAG chain empty" || echo "NO")"
echo "  Connected OK:      $([ $HAS_CONNECTED -eq 1 ] && echo "YES" || echo "NO")"

echo ""
if [[ $HAS_HALT_TIMEOUT -eq 1 ]]; then
  echo "DIAGNOSIS: JTAG TAP responds, but core won't halt."
  echo ""
  echo "The JTAG physical layer works. The problem is inside the debug module:"
  echo "  - J-Link writes dmcontrol.haltreq=1"
  echo "  - Polls dmstatus.allhalted - never goes high"
  echo ""
  echo "Possible causes:"
  echo "  1. BOARD STATE CORRUPTED - most likely after multiple reprogram cycles"
  echo "     → FIX: Full power cycle (switch OFF, wait 10s, switch ON)"
  echo "  2. Core clock not running (MMCM not locked)"
  echo "     → Debug module JTAG side works (TCK domain) but system side stuck"
  echo "  3. Debug module ndmreset stuck"
  echo ""
  echo "RECOMMENDATION: Full power cycle, then reprogram and retry."
elif [[ $HAS_NO_DEVICE -eq 1 ]]; then
  echo "DIAGNOSIS: No JTAG TAP detected at all."
  echo ""
  echo "Either:"
  echo "  1. PMOD0 wiring is wrong"
  echo "  2. FPGA not configured (bitstream not loaded)"
  echo "  3. MMCM not locked (JTAG TAP needs clock)"
  echo ""
  echo "Check J55 PMOD upper row wiring:"
  echo "  PMOD0_4 (G6) → J-Link TDI"
  echo "  PMOD0_5 (H6) → J-Link TMS"
  echo "  PMOD0_6 (J6) → J-Link TCK"
  echo "  PMOD0_7 (J7) → J-Link TDO"
  echo "  Pin 10        → J-Link GND"
  echo "  Pin 12        → J-Link VTref"
elif [[ $HAS_CONNECTED -eq 1 ]]; then
  echo "DIAGNOSIS: J-Link connected successfully!"
  echo "Try starting GDB Server now."
fi

echo ""
rm -f "$JLINK_CMDS" 2>/dev/null
