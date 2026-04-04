#!/usr/bin/env bash
set -euo pipefail
#
# run_opensbi_linux_closure3.sh
# Complete SOP for the third closure loop: OpenSBI -> Linux kernel entry
#
# This is the SINGLE entry point for the reproducible Linux bring-up flow.
# It does NOT modify the stable baremetal default flow.
#
# Prerequisites:
#   1. ZCU104 board powered on and connected via JTAG+UART
#   2. Stable bit loaded + PS DDR initialized:
#        bash /root/chipyard/fpga/scripts/run_ps_ddr_init.sh
#   3. J-Link GDB Server running on Windows host (start_jlink_gdb_server.bat)
#   4. Serial terminal open on UART (115200 8N1)
#
# Architecture:
#   --batch mode uses a SINGLE GDB session for load + walk (no reconnect).
#   Interactive mode uses separate load then interactive GDB session.
#
# Usage:
#   bash /root/chipyard/fpga/linux-bringup/scripts/run_opensbi_linux_closure3.sh [options]
#
# Options:
#   --skip-build    Skip OpenSBI rebuild (use existing fw_payload.bin)
#   --skip-load     Skip DDR load (assume already loaded)
#   --host H        J-Link host (default: auto-detect gateway)
#   --port P        J-Link port (default: 2331)
#   --batch         Single-session load + walk (no interactive GDB)
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRINGUP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FPGA_DIR="$(cd "$BRINGUP_DIR/.." && pwd)"

OPENSBI_BUILD=/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware
FW_BIN="${OPENSBI_BUILD}/fw_payload.bin"
FW_ELF="${OPENSBI_BUILD}/fw_payload.elf"
DTB="${BRINGUP_DIR}/demo-assets/dtb/chipyard-zcu104-linux.dtb"
OBSERVE="${SCRIPT_DIR}/opensbi_linux_observe.gdb"

GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
HOST="$(ip route | awk '/default/ {print $3; exit}')"
PORT=2331
CHUNK_SIZE=$((1 * 1024 * 1024))        # 1 MB per chunk

SKIP_BUILD=0
SKIP_LOAD=0
BATCH_MODE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1; shift ;;
    --skip-load)  SKIP_LOAD=1; shift ;;
    --host)       HOST="$2"; shift 2 ;;
    --port)       PORT="$2"; shift 2 ;;
    --batch)      BATCH_MODE=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

echo "================================================================"
echo "  ZCU104 Linux Bring-up: Third Closure Loop SOP"
echo "  OpenSBI -> Linux kernel entry"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================"
echo ""

# ---------- J-Link connectivity pre-check ----------
check_jlink() {
  echo "[check] J-Link GDB Server at $HOST:$PORT ..."
  if timeout 5 bash -c "echo >/dev/tcp/$HOST/$PORT" 2>/dev/null; then
    echo "[ok] J-Link reachable"
    return 0
  else
    echo "[error] Cannot reach J-Link GDB Server at $HOST:$PORT" >&2
    echo "  On Windows host, run:" >&2
    echo '  "C:\Program Files\SEGGER\JLink\JLinkGDBServerCL.exe" -device RISC-V -if JTAG -speed 1000 -port 2331 -localhostonly 0' >&2
    return 1
  fi
}

# ============================================================
# Phase 1: Build OpenSBI FW_PAYLOAD
# ============================================================
echo "[phase 1] OpenSBI FW_PAYLOAD build"

if (( SKIP_BUILD )); then
  echo "  Skipped (--skip-build)"
  if [[ ! -f "$FW_BIN" ]]; then
    echo "[error] fw_payload.bin not found: $FW_BIN" >&2
    echo "  Run without --skip-build to rebuild." >&2
    exit 2
  fi
else
  echo "  Building..."
  bash "${SCRIPT_DIR}/build_opensbi_linux_payload.sh"
fi

for f in "$FW_BIN" "$FW_ELF" "$DTB"; do
  [[ -f "$f" ]] || { echo "[error] Required file missing: $f" >&2; exit 2; }
done

echo "  fw_payload.bin: $(stat -c %s "$FW_BIN") bytes"
echo "  fw_payload.elf: $FW_ELF"
echo ""

# ============================================================
# Route: BATCH mode (single GDB session: load + walk)
#    or: INTERACTIVE mode (separate load, then interactive GDB)
# ============================================================

if (( BATCH_MODE )); then
  # ============================================================
  # BATCH: Stable J-Link load path, then single GDB session for restore + walk.
  # ============================================================
  echo "[batch] Single-session load + walk"
  echo ""

  if (( !SKIP_LOAD )); then
    echo "[phase 2] Stable J-Link chunked load + DTB"
    bash "${SCRIPT_DIR}/load_opensbi_linux_payload.sh" --host "$HOST" --port "$PORT"
    echo ""
  else
    check_jlink || exit 3
  fi

  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT

  # --- Compute expected verification values from binary ---
  EXPECT_OPENSBI=$(od -A n -t x4 -N 4 "$FW_BIN" | tr -d ' ')
  EXPECT_LINUX=$(od -A n -t x4 -N 4 -j $((0x200000)) "$FW_BIN" | tr -d ' ')
  EXPECT_DTB=$(od -A n -t x4 -N 4 "$DTB" | tr -d ' ')

  echo "[info] Expected memory values (from binary):"
  echo "  OpenSBI @ 0x80000000: 0x$EXPECT_OPENSBI"
  echo "  Linux   @ 0x80200000: 0x$EXPECT_LINUX"
  echo "  DTB     @ 0x82400000: 0x$EXPECT_DTB"
  echo ""

  # --- Generate single master GDB command file ---
  MASTER_GDB="$TMPDIR/master.gdb"
  {
    echo "set pagination off"
    echo "set confirm off"
    echo "set remotetimeout 300"
    echo "set breakpoint auto-hw off"
    echo "set architecture riscv:rv64"
    echo ""
    echo "target remote $HOST:$PORT"
    echo "monitor halt"
    echo ""
    echo "# Load symbol files for debugging before semantic restore"
    echo "add-symbol-file $FW_ELF"
    echo "add-symbol-file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux 0x80200000"
    echo ""

    cat <<PYRESTORE
python
import gdb

  def try_read(addr, label, expected):
    try:
        result = gdb.execute(f"x/1wx {addr}", to_string=True).strip()
        gdb.write(f"[verify] {label}: {result}  (expect {expected})\\n")
        return True
    except gdb.error as e:
        gdb.write(f"[verify] {label}: FAILED - {e}\\n")
        return False

def try_write(addr, val=0):
    try:
        gdb.execute(f"set {{long long}}{addr} = {val}")
        return True
    except gdb.error:
        return False

    def sym(name):
      return int(gdb.parse_and_eval(name))

    def addr(name):
      return int(gdb.parse_and_eval(f"(unsigned long)&{name}"))

    gdb.write("\\n=== PHASE: VERIFY + SEMANTIC RESTORE ===\\n\\n")
v1 = try_read("0x80000000", "OpenSBI", "0x$EXPECT_OPENSBI")
v2 = try_read("0x80200000", "Linux  ", "0x$EXPECT_LINUX")
v3 = try_read("0x82400000", "DTB    ", "0x$EXPECT_DTB")

if v1 and v2 and v3:
    gdb.write("[ok] All verify passed -- progbuf works after ndmreset!\\n")
else:
  gdb.write("[warn] Some verify failed. Proceeding with semantic restore anyway.\\n")

restore_from_elf = {
  "_load_start": sym("_fw_start"),
  "_link_start": sym("_fw_start"),
  "_link_end": sym("_fw_reloc_end"),
  "__fw_rw_offset": sym("_fw_rw_start") - sym("_fw_start"),
}
zero_syms = [
  "_relocate_lottery",
  "_boot_status",
  "_debug_last_mcause",
  "_debug_last_mtval",
  "_debug_last_mepc",
  "_debug_stage",
  "_debug_value0",
  "_debug_value1",
  "_debug_value2",
  "_debug_value3",
]

for name, value in restore_from_elf.items():
  try_write(f"0x{addr(name):x}", value)

for name in zero_syms:
  try_write(f"0x{addr(name):x}", 0)

bss_start = sym("_bss_start")
bss_end = sym("_bss_end")
zeroed = 0
for slot in range(bss_start, bss_end, 8):
  if try_write(f"0x{slot:x}", 0):
    zeroed += 1

gdb.write(
  f"[info] restored metadata: _load_start=0x{restore_from_elf['_load_start']:x} "
  f"_link_start=0x{restore_from_elf['_link_start']:x} "
  f"_link_end=0x{restore_from_elf['_link_end']:x} "
  f"__fw_rw_offset=0x{restore_from_elf['__fw_rw_offset']:x}\\n"
)
gdb.write(f"[info] bss zeroed slots: {zeroed} (0x{bss_start:x}..0x{bss_end:x})\\n")
end
PYRESTORE
    echo ""

  echo "# Entry state: a0=hartid=0, a1=dtb, pc=OpenSBI _start"
  echo "set \$a0 = 0"
  echo "set \$a1 = 0x82400000"
  echo "set \$a2 = 0"
  echo "set \$pc = 0x80000000"
  echo "printf \"[ok] Entry state set: pc=0x80000000 a0=0 a1=0x82400000\\n\""
  echo "printf \"[state] early boot window after restore:\\n\""
  echo "x/6gx 0x800200a8"
  echo ""

    # ---- BOOT phase: test progbuf, then walk or free-run ----
    cat <<'BOOTPHASE'
python
import gdb, time

def safe_exec(cmd):
    """Execute GDB command, return (success, result_string)."""
    try:
        result = gdb.execute(cmd, to_string=True)
        return True, result.strip()
    except gdb.error as e:
        return False, str(e)

gdb.write("\n=== PHASE: BOOT ===\n\n")

# Test if progbuf works by reading BootROM (on-chip, always accessible)
ok, result = safe_exec("x/1wx 0x10000")
if ok:
    gdb.write(f"[ok] Progbuf works! BootROM @ 0x10000: {result}\n")
    gdb.write("[info] Full walk possible. Proceeding...\n\n")
    # Will fall through to walk commands below
else:
    gdb.write(f"[warn] Progbuf FAILED: {result}\n")
    gdb.write("[info] Cannot stepi/read memory. Booting via detach (J-Link resumes core).\n")
    gdb.write("[info] >>> Watch UART (COM port, 115200 8N1) for OpenSBI output! <<<\n\n")
    gdb.write("[info] Entry state: pc=0x80000000 a0=0 a1=0x82400000\n")
    gdb.write("[info] Detaching from target...\n")
    gdb.execute("detach")
    gdb.execute("quit")
end
BOOTPHASE

    # ---- Full WALK phase (only reached if progbuf works) ----
    # Use timed run/halt checkpoints instead of blocking breakpoints.
    cat <<'WALK'
python
import gdb, time

def safe(cmd):
    try:
        return gdb.execute(cmd, to_string=True).strip()
    except gdb.error as e:
        return f"ERROR: {e}"

gdb.write("\n=== PHASE: WALK (timed run checkpoints) ===\n\n")
gdb.write("--- Diagnostic A: disassemble first 8 instructions at 0x80000000 ---\n")
gdb.write(safe("x/8i 0x80000000") + "\n\n")
gdb.write("--- Diagnostic B: current CPU state ---\n")
gdb.write(safe("info reg pc a0 a1 a2 sp ra") + "\n\n")

last_pc = None
for d in (0.01, 0.05, 0.20, 1.00, 2.00):
    gdb.execute("monitor go")
    time.sleep(d)
    gdb.execute("monitor halt")

    try:
        pc = int(gdb.parse_and_eval("$pc"))
        pc_s = f"0x{pc:016x}"
    except Exception as e:
        pc = None
        pc_s = f"<unavailable: {e}>"

    stage = safe("x/1gx 0x800200f0")
    trap = safe("x/3gx 0x800200d8")
  boot = safe("x/6gx 0x800200a8")

    gdb.write(f"[run {d:>4.2f}s] pc={pc_s}\n")
  gdb.write(f"  boot : {boot}\n")
    gdb.write(f"  stage: {stage}\n")
    gdb.write(f"  trap : {trap}\n")

    if pc is not None and last_pc is not None and pc != last_pc:
        gdb.write("  note : PC advanced\n")
    last_pc = pc

final_trap = safe("x/3gx 0x800200d8")
if last_pc is not None:
  if 0x80200000 <= last_pc < 0x90000000:
    gdb.write("\n[result] advanced_to_linux_entry_or_later\n")
  elif "0x00000000800003be" in final_trap:
    gdb.write("\n[result] trapped_at_0x800003be\n")
  elif "0x0000000080012ec6" in final_trap:
    gdb.write("\n[result] trapped_at_0x80012ec6\n")
  elif 0x80000418 <= last_pc < 0x80000428:
    gdb.write("\n[result] waiting_for_boot_hart\n")
  elif 0x80000180 <= last_pc < 0x800001c0:
    gdb.write("\n[result] waiting_for_relocate_copy_done\n")
  elif 0x80000000 <= last_pc < 0x80200000:
    gdb.write("\n[result] still_in_opensbi_other\n")
  else:
    gdb.write("\n[result] pc_unexpected_range\n")

gdb.write("\n=== WALK CHECKPOINTS COMPLETE ===\n")
end
WALK

    echo ""
    echo "detach"
    echo "quit"
  } > "$MASTER_GDB"

  # --- Run single GDB session ---
  LOGDIR="${BRINGUP_DIR}/logs"
  mkdir -p "$LOGDIR"
  LOGFILE="$LOGDIR/closure3_$(date +%Y%m%d_%H%M%S).log"

  echo "[info] Running single GDB session (load + walk)..."
  echo "[info] Log: $LOGFILE"
  echo "================================================================"
  "$GDB" -batch -x "$MASTER_GDB" 2>&1 | tee "$LOGFILE" || true
  echo "================================================================"
  echo ""
  echo "[done] Batch walk complete. Log: $LOGFILE"

else
  # ============================================================
  # INTERACTIVE: Separate load, then interactive GDB
  # ============================================================

  # Phase 2: Load into DDR
  echo "[phase 2] Load FW_PAYLOAD + DTB into DDR"
  if (( SKIP_LOAD )); then
    echo "  Skipped (--skip-load)"
  else
    check_jlink || exit 3
    echo "  Using chunked restore for reliability..."
    bash "${SCRIPT_DIR}/load_opensbi_linux_payload.sh" --host "$HOST" --port "$PORT"
  fi
  echo ""

  # Phase 3: Interactive GDB
  echo "[phase 3] Interactive GDB session"
  echo ""
  check_jlink || exit 3

  echo "  Quick reference:"
  echo "    source ${OBSERVE}"
  echo ""
  echo "  Key commands after sourcing:"
  echo "    pverify              - verify memory at key addresses"
  echo "    ppmp                 - dump PMP configuration"
  echo "    walk_opensbi_to_linux - automated full walkthrough"
  echo "    bmret + pmret        - break at mret, dump pre-mret state"
  echo "    stepi after bmret    - step into Linux"
  echo "    bkernel_head         - break at _start_kernel"
  echo "    bkernel_bss          - break at first BSS store"
  echo "    restoreopensbiearly  - restore metadata/state and restart from _start"
  echo "    recleanopensbi       - alias of restoreopensbiearly"
  echo ""
  echo "  Typical manual flow:"
  echo "    1. pverify           - confirm load OK"
  echo "    2. bmret             - run to mret"
  echo "    3. pmret             - dump full state"
  echo "    4. stepi             - enter Linux"
  echo "    5. pkernel           - see where we are"
  echo "    6. bkernel_bss       - run to first store"
  echo "    7. stepi             - execute first store"
  echo ""

  exec "$GDB" "$FW_ELF" \
    -ex "source ${OBSERVE}"
fi
