#!/usr/bin/env bash
# jlink_scan_chain.sh — Scan JTAG chain via J-Link Commander
#
# Runs JLink.exe to scan the JTAG chain and report what TAPs are found.
# Uses the "connect" command which triggers full JTAG chain detection.
#
# Usage: bash scripts/jlink_scan_chain.sh
#
# Output: JTAG chain info, IDCODE, TAP info

set -uo pipefail

JLINK_EXE='C:\Program Files\SEGGER\JLink\JLink.exe'
JLINK_SERIAL="${JLINK_USB_SERIAL:-601012542}"

# Create JLink command script
# "connect" triggers full JTAG chain scan. The -Device/-IF/-Speed on
# the command line pre-fill the interactive prompts so connect proceeds
# without user input.
JLINK_CMDS=$(mktemp /mnt/c/Windows/Temp/jlink_scan_XXXX.jlink 2>/dev/null || mktemp /tmp/jlink_scan_XXXX.jlink)
JLINK_CMDS_WIN=$(wslpath -w "$JLINK_CMDS" 2>/dev/null || echo "$JLINK_CMDS")

cat > "$JLINK_CMDS" << 'CMDS'
connect
sleep 1000
q
CMDS

echo "=== J-Link JTAG Chain Scan ==="
echo "JLink.exe: $JLINK_EXE"
echo "Serial: $JLINK_SERIAL"
echo ""

# Run JLink.exe — the "connect" command will scan the chain.
# -Device RISC-V -IF JTAG -Speed 1000 pre-fill the prompts.
# -JTAGConf 0,0  = single TAP chain (no other TAPs before target).
# -ExitOnError 0 = continue even if connection fails (so we see chain info).
SCAN_OUTPUT=$(powershell.exe -NoProfile -Command "& '$JLINK_EXE' \
  -SelectEmuBySN $JLINK_SERIAL \
  -Device RISC-V -IF JTAG -Speed 1000 \
  -JTAGConf 0,0 \
  -ExitOnError 0 \
  -CommandFile '$JLINK_CMDS_WIN' 2>&1" 2>&1)

echo "$SCAN_OUTPUT"
echo ""
echo "=== ANALYSIS ==="

# Parse results — look for IDCODE, TAP info, or errors
if echo "$SCAN_OUTPUT" | grep -qi "IDCODE\|Found.*device\|TotalIRLen\|JTAG chain"; then
  echo "JTAG TAP(s) detected:"
  echo "$SCAN_OUTPUT" | grep -i "IDCODE\|TAP\|Found.*device\|CoreID\|IR len\|TotalIR\|NumDevices\|scan chain"
elif echo "$SCAN_OUTPUT" | grep -qi "Cannot find\|No JTAG\|No device\|Can not connect"; then
  echo "NO JTAG TAP detected on chain."
  echo ""
  echo "J55 PMOD upper row JTAG wiring:"
  echo "  PMOD0_4 (G6) = TDI"
  echo "  PMOD0_5 (H6) = TMS"
  echo "  PMOD0_6 (J6) = TCK"
  echo "  PMOD0_7 (J7) = TDO"
  echo "  Pin 10        = GND"
  echo "  Pin 12        = VTref"
fi

if echo "$SCAN_OUTPUT" | grep -qi "Timeout.*halt\|halt.*timeout"; then
  echo ""
  echo "TAP found but HALT FAILED — core clock may not be running or DMI is stuck."
  echo "The JTAG TAP responds (on TCK) but the debug module system side (on core clock) doesn't."
fi

if echo "$SCAN_OUTPUT" | grep -qi "VTref.*0\.0\|VTref=0\."; then
  echo ""
  echo "WARNING: VTref is 0V — target not powered or VTREF wire not connected."
fi

rm -f "$JLINK_CMDS" 2>/dev/null
