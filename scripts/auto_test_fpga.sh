#!/usr/bin/env bash
# auto_test_fpga.sh — All-in-one: program FPGA + diagnose + J-Link test + LED
#
# What this script does (fully automated):
#   Phase A: Program FPGA via XSDB (run_ps_ddr_init.sh)
#   Phase B: Run XSDB-based diagnostics (DDR, PCAP status, AFIFM6)
#   Phase C: Kill/restart J-Link GDB Server on Windows
#   Phase D: Run GDB smoke test (halt core, read PC, DDR test, toggle LED, SDHCI)
#
# Usage:
#   bash scripts/auto_test_fpga.sh [--skip-program] [--skip-jlink-restart]
#
# Options:
#   --skip-program      Skip FPGA programming (assume already done)
#   --skip-jlink-restart Don't restart J-Link GDB Server
#
# Outputs:
#   All results logged to /tmp/auto_test_fpga_<timestamp>.log
#   Results also printed to stdout

set -uo pipefail

# ============================================================
# Configuration
# ============================================================
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/tmp/auto_test_fpga_${TIMESTAMP}.log"

# Tools
GDB="${GDB:-/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb}"
XSDB_BAT="${XSDB_BAT:-/mnt/e/PRO_APP/xilinx/Vivado/2021.2/bin/xsdb.bat}"
JLINK_GDB_SERVER='C:\Program Files\SEGGER\JLink\JLinkGDBServerCL.exe'
JLINK_HOST="${JLINK_HOST:-172.19.128.1}"
JLINK_PORT="${JLINK_PORT:-2331}"
JLINK_SERIAL="${JLINK_USB_SERIAL:-601012542}"
POST_PROGRAM_WAIT_SECS="${POST_PROGRAM_WAIT_SECS:-8}"
PRE_JLINK_WAIT_SECS="${PRE_JLINK_WAIT_SECS:-10}"

# Config
ZCU104_CFG="${CHIPYARD_ZCU104_CFG:-RocketZCU104LinuxBringupConfig}"
BIT_DIR="${FPGA_DIR}/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.${ZCU104_CFG}/obj"
BIT_FILE="${BIT_DIR}/ZCU104FPGATestHarness.bit"
PSU_INIT="${BIT_DIR}/ip/zcu104ps/psu_init.tcl"

# Flags
SKIP_PROGRAM=0
SKIP_JLINK_RESTART=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-program) SKIP_PROGRAM=1; shift ;;
    --skip-jlink-restart) SKIP_JLINK_RESTART=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ============================================================
# Helpers
# ============================================================
tee_log() {
  tee -a "$LOG_FILE"
}

log() {
  echo "$@" | tee_log
}

banner() {
  local msg="$1"
  log ""
  log "================================================================"
  log "  $msg"
  log "================================================================"
}

check_file() {
  local f="$1" label="$2"
  if [[ -f "$f" ]]; then
    log "[OK] $label: $f"
    return 0
  else
    log "[FAIL] $label not found: $f"
    return 1
  fi
}

# ============================================================
# Pre-flight checks
# ============================================================
banner "AUTO TEST — ZCU104 FPGA  (${TIMESTAMP})"
log "Config    : ${ZCU104_CFG}"
log "Bitstream : ${BIT_FILE}"
log "psu_init  : ${PSU_INIT}"
log "Log file  : ${LOG_FILE}"

PREFLIGHT_FAIL=0
check_file "$BIT_FILE" "Bitstream" || PREFLIGHT_FAIL=1
check_file "$PSU_INIT" "psu_init.tcl" || PREFLIGHT_FAIL=1
check_file "$GDB" "GDB" || PREFLIGHT_FAIL=1

if [[ $PREFLIGHT_FAIL -ne 0 ]]; then
  log "[ABORT] Pre-flight check failed"
  exit 1
fi

log "[OK] Bitstream size: $(stat -c %s "$BIT_FILE") bytes, date: $(stat -c '%y' "$BIT_FILE")"

# ============================================================
# Phase A: Program FPGA via XSDB
# ============================================================
if [[ $SKIP_PROGRAM -eq 0 ]]; then
  banner "Phase A: Program FPGA + PS DDR init"

  log "[A] Running run_ps_ddr_init.sh ..."
  PROGRAM_LOG="/tmp/fpga_program_${TIMESTAMP}.log"
  bash "${SCRIPT_DIR}/run_ps_ddr_init.sh" --bit "$BIT_FILE" --psu-init "$PSU_INIT" 2>&1 | tee "$PROGRAM_LOG" | tee_log
  # cmd.exe may not propagate exit codes through WSL correctly,
  # so also check the output for XSDB errors.
  if grep -qi 'ERROR\|error.*exit\|psu_init.*fail\|no targets found' "$PROGRAM_LOG" 2>/dev/null; then
    log ""
    log "[A] FAIL: FPGA programming had errors (see above)"
    log "[A] Check log: $PROGRAM_LOG"
    log ""
    log "Common fixes:"
    log "  1. Power-cycle ZCU104 (OFF/wait 10s/ON), then re-run"
    log "  2. Ensure USB JTAG cable is connected"
    log "  3. Close Vivado Hardware Manager if open"
    exit 2
  fi
  if ! grep -q 'PS DDR init.*FPGA download.*completed\|isolation removal' "$PROGRAM_LOG" 2>/dev/null; then
    log ""
    log "[A] WARN: Cannot confirm FPGA programming completed successfully"
    log "[A] Check log: $PROGRAM_LOG"
    # Don't exit — continue with diagnostics
  else
    log ""
    log "[A] PASS: FPGA programming completed"
  fi

  # Give the freshly loaded PL image time to come fully out of reset so the
  # hardware heartbeat LED can be observed before any J-Link traffic starts.
  log "[A] Waiting ${POST_PROGRAM_WAIT_SECS}s for PL to stabilize and DS39 heartbeat to appear ..."
  sleep "$POST_PROGRAM_WAIT_SECS"
else
  banner "Phase A: SKIPPED (--skip-program)"
fi

# ============================================================
# Phase B: XSDB-based diagnostics
# ============================================================
banner "Phase B: XSDB diagnostics"
DIAG_TCL="${SCRIPT_DIR}/xsdb_diag_after_program.tcl"
DIAG_LOG="/tmp/fpga_diag_${TIMESTAMP}.log"

if [[ -f "$DIAG_TCL" ]]; then
  log "[B] Running XSDB diagnostics ..."

  # Create Windows wrapper to run the TCL script
  WIN_TCL=$(wslpath -w "$DIAG_TCL" 2>/dev/null || echo "$DIAG_TCL")
  WIN_XSDB_BAT=$(wslpath -w "$XSDB_BAT" 2>/dev/null || echo "$XSDB_BAT")
  WIN_WRAPPER=$(mktemp /mnt/c/Windows/Temp/xsdb_diag_XXXX.cmd 2>/dev/null || mktemp /tmp/xsdb_diag_XXXX.cmd)
  WIN_WRAPPER_CMD=$(wslpath -w "$WIN_WRAPPER" 2>/dev/null || echo "$WIN_WRAPPER")

  cat > "$WIN_WRAPPER" <<CMD
@echo off
pushd C:\\Windows\\Temp
call "$WIN_XSDB_BAT" -eval "source {$WIN_TCL}"
set EC=%ERRORLEVEL%
popd
exit /b %EC%
CMD

  if cmd.exe /c "$WIN_WRAPPER_CMD" 2>&1 | tee "$DIAG_LOG" | tee_log; then
    log ""
    log "[B] XSDB diagnostics completed"
  else
    log ""
    log "[B] XSDB diagnostics had errors (may be non-fatal)"
  fi
  rm -f "$WIN_WRAPPER" 2>/dev/null
else
  log "[B] SKIP: diagnostic TCL not found ($DIAG_TCL)"
fi

# ============================================================
# Phase B2: J-Link JTAG chain scan (independent of GDB Server)
# ============================================================
banner "Phase B2: J-Link JTAG chain scan"
JLINK_SCAN="${SCRIPT_DIR}/jlink_scan_chain.sh"

if [[ -f "$JLINK_SCAN" ]]; then
  log "[B2] Scanning JTAG chain via J-Link Commander ..."
  log "[B2] This does NOT connect to the RISC-V core, just reads IDCODEs."

  # Kill hw_server first — it may be holding the Xilinx JTAG lock
  # which shouldn't affect PMOD JTAG, but let's be safe
  powershell.exe -NoProfile -Command 'Stop-Process -Name hw_server -ErrorAction SilentlyContinue' 2>/dev/null || true
  sleep 1

  SCAN_LOG="/tmp/jlink_scan_${TIMESTAMP}.log"
  JLINK_USB_SERIAL="$JLINK_SERIAL" bash "$JLINK_SCAN" 2>&1 | tee "$SCAN_LOG" | tee_log

  if grep -qi "IDCODE" "$SCAN_LOG" 2>/dev/null; then
    log "[B2] JTAG TAP detected"
  else
    log "[B2] WARN: No IDCODE found — J-Link may not see PL JTAG TAP"
    log "[B2] Check J55 wiring: TDI=PMOD0_4(G6) TMS=PMOD0_5(H6) TCK=PMOD0_6(J6) TDO=PMOD0_7(J7)"
  fi
else
  log "[B2] SKIP: jlink_scan_chain.sh not found"
fi

# ============================================================
# Phase C: Kill/restart J-Link GDB Server
# ============================================================
if [[ $SKIP_JLINK_RESTART -eq 0 ]]; then
  banner "Phase C: Restart J-Link GDB Server"

  log "[C.-1] Waiting ${PRE_JLINK_WAIT_SECS}s before any J-Link attach ..."
  log "[C.-1] Confirm DS39 is blinking before continuing."
  sleep "$PRE_JLINK_WAIT_SECS"

  log "[C.0] Killing hw_server (may hold JTAG chain) ..."
  powershell.exe -NoProfile -Command 'Stop-Process -Name hw_server -ErrorAction SilentlyContinue' 2>/dev/null || true

  log "[C.1] Killing existing J-Link processes ..."
  powershell.exe -NoProfile -Command 'Stop-Process -Name JLinkGDBServerCL,JLink -ErrorAction SilentlyContinue' 2>/dev/null || true
  sleep 3

  log "[C.2] Starting JLinkGDBServerCL (port ${JLINK_PORT}, -noir) ..."
  # JTAG is on PMOD0 (single TAP, JTAGConf 0,0 = no TAPs before target).
  # Use -noir to skip initial reset (jtag_srst_n is not connected).
  # Use -select USB=serial to pick the right J-Link probe.
  powershell.exe -NoProfile -Command "Start-Process -FilePath '${JLINK_GDB_SERVER}' \
    -ArgumentList '-select','USB=${JLINK_SERIAL}','-device','RISC-V','-endian','little',\
    '-if','JTAG','-speed','1000','-JTAGConf','0,0','-port','${JLINK_PORT}',\
    '-LocalhostOnly','0','-noir' \
    -WindowStyle Normal" 2>/dev/null

  log "[C.3] Waiting 8s for J-Link to initialize ..."
  sleep 8

  # Verify J-Link is reachable
  if nc -z -w 3 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
    log "[C] PASS: J-Link GDB Server reachable at ${JLINK_HOST}:${JLINK_PORT}"
  else
    log "[C] WARN: Cannot reach J-Link at ${JLINK_HOST}:${JLINK_PORT}"
    log "[C] Trying with default reset (no -noir) ..."

    powershell.exe -NoProfile -Command 'Stop-Process -Name JLinkGDBServerCL -ErrorAction SilentlyContinue' 2>/dev/null || true
    sleep 2

    powershell.exe -NoProfile -Command "Start-Process -FilePath '${JLINK_GDB_SERVER}' \
      -ArgumentList '-select','USB=${JLINK_SERIAL}','-device','RISC-V','-endian','little',\
      '-if','JTAG','-speed','1000','-JTAGConf','0,0','-port','${JLINK_PORT}',\
      '-LocalhostOnly','0' \
      -WindowStyle Normal" 2>/dev/null

    sleep 8

    if nc -z -w 3 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
      log "[C] PASS: J-Link GDB Server reachable (without -noreset)"
    else
      log "[C] FAIL: J-Link GDB Server not reachable on any attempt"
      log ""
      log "Troubleshooting:"
      log "  1. Check J-Link USB connection to PC"
      log "  2. Open J-Link GDB Server GUI manually"
      log "  3. Check if another process (JLink.exe) is using the probe"
      log "  4. Power cycle ZCU104 and retry"
    fi
  fi

  # Also check relay port
  if [[ "$JLINK_PORT" == "2331" ]]; then
    if nc -z -w 2 "$JLINK_HOST" 12331 2>/dev/null; then
      log "[C] INFO: Relay port 12331 also reachable"
    fi
  fi
else
  banner "Phase C: SKIPPED (--skip-jlink-restart)"
fi

# ============================================================
# Phase D: GDB smoke test
# ============================================================
banner "Phase D: GDB smoke test (LED + DDR + SDHCI)"
SMOKE_GDB="${SCRIPT_DIR}/jlink_smoke_test.gdb"
SMOKE_LOG="/tmp/jlink_smoke_${TIMESTAMP}.log"

if [[ ! -f "$SMOKE_GDB" ]]; then
  log "[D] SKIP: smoke test GDB script not found ($SMOKE_GDB)"
else
  # Try port 2331 first, then 12331
  PORTS_TO_TRY="${JLINK_PORT}"
  if [[ "$JLINK_PORT" == "2331" ]]; then
    PORTS_TO_TRY="2331,12331"
  fi

  log "[D] Running GDB smoke test ..."
  log "[D] Trying ports: ${PORTS_TO_TRY}"
  JLINK_HOST="$JLINK_HOST" JLINK_PORT="$PORTS_TO_TRY" \
    timeout 60 "$GDB" -batch -x "$SMOKE_GDB" 2>&1 | tee "$SMOKE_LOG" | tee_log
  GDB_RC=${PIPESTATUS[0]}

  log ""
  if [[ $GDB_RC -eq 0 ]]; then
    log "[D] PASS: GDB smoke test completed successfully"
  else
    log "[D] FAIL: GDB smoke test failed (exit code $GDB_RC)"
    log "[D] Check log: $SMOKE_LOG"
  fi
fi

# ============================================================
# Final Summary
# ============================================================
banner "FINAL SUMMARY"
log "Timestamp : ${TIMESTAMP}"
log "Config    : ${ZCU104_CFG}"
log "Bitstream : ${BIT_FILE}"
log ""
log "Logs:"
log "  Full log     : ${LOG_FILE}"
[[ $SKIP_PROGRAM -eq 0 ]] && log "  Program log  : /tmp/fpga_program_${TIMESTAMP}.log"
[[ -f "$DIAG_TCL" ]] && log "  Diag log     : ${DIAG_LOG}"
log "  Smoke log    : ${SMOKE_LOG}"
log ""
log "If LED DS39 is ON, the Rocket core was halted and GPIO was toggled successfully."
log "If LED is OFF, either J-Link connection failed or core couldn't be halted."
log ""
log "Next steps if smoke test passed:"
log "  1. Run full Linux boot: bash scripts/start_linux_boot.sh"
log "  2. Manual GDB: $GDB -x scripts/linux_boot.gdb"
log ""
log "Next steps if smoke test failed:"
log "  1. Power cycle ZCU104 (physical POR button)"
log "  2. Re-run: bash scripts/auto_test_fpga.sh"
log "  3. If still failing, try old bitstream:"
log "     bash scripts/auto_test_fpga.sh --bit <old.bit>"
