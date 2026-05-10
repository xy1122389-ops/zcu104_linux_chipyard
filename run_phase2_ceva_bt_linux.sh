#!/usr/bin/env bash
# run_phase2_ceva_bt_linux.sh — Phase 2: CEVA BT5.2 Linux driver boot verification
#
# Tests: ceva_bt52.ko insmod on ZCU104 + Rocket + Fedora
# Uses new fw_payload.bin with CONFIG_BT=m + initramfs(bluetooth.ko + ceva_bt52.ko)
# Uses chipyard-zcu104-fedora.dtb with CEVA node (compatible = "ceva,rw-dm-bt52")
#
# Prerequisites:
#   - ZCU104 powered on (XSDB accessible for PS DDR init)
#   - J-Link 127.0.0.1:3333 active
#   - New fw_payload.bin built (via rebuild_payload.sh)
#
# Usage:
#   KERNEL_RUN_SECS=120 bash run_phase2_ceva_bt_linux.sh
#   SKIP_DDR_INIT=1 KERNEL_RUN_SECS=120 bash run_phase2_ceva_bt_linux.sh   # skip PS DDR init
#   PHASE2_CFG=RocketZCU104Phase0bConfig bash run_phase2_ceva_bt_linux.sh

set -euo pipefail

JLINK_HOST="${JLINK_HOST:-127.0.0.1}"
JLINK_PORT="${JLINK_PORT:-3333}"
KERNEL_RUN_SECS="${KERNEL_RUN_SECS:-120}"
# PHASE2_CFG: which bitstream config for PS DDR init (default = Phase0b)
PHASE2_CFG="${PHASE2_CFG:-RocketZCU104Phase0bConfig}"
# Set SKIP_DDR_INIT=1 to skip PS DDR init (if board already programmed and DDR ready)
SKIP_DDR_INIT="${SKIP_DDR_INIT:-0}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD_BIN="${SCRIPT_DIR}/linux-bringup/payload/fw_payload.bin"
CHUNK_DIR="/tmp/fw_chunks_phase2"
GDB_BIN="/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb"
DTB="${SCRIPT_DIR}/linux-bringup/dtb/chipyard-zcu104-fedora.dtb"
GDB_SCRIPT="${SCRIPT_DIR}/scripts/linux_boot_phase2.gdb"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*" >&2; exit 1; }

echo "================================================================"
echo "  ZCU104 Phase 2: CEVA BT5.2 Linux Driver Boot Verification"
echo "================================================================"
echo "  Payload  : $PAYLOAD_BIN"
echo "  DTB      : $DTB"
echo "  Run secs : $KERNEL_RUN_SECS"
echo "  J-Link   : $JLINK_HOST:$JLINK_PORT"
echo "  DDR init : $([ "$SKIP_DDR_INIT" = "1" ] && echo SKIP || echo "YES (cfg=$PHASE2_CFG)")"
echo ""

# Preflight checks
[[ -f "$PAYLOAD_BIN" ]] || fail "fw_payload.bin not found: $PAYLOAD_BIN"
[[ -f "$DTB" ]] || fail "DTB not found: $DTB"
[[ -x "$GDB_BIN" ]] || fail "GDB not found: $GDB_BIN"
[[ -f "$GDB_SCRIPT" ]] || fail "GDB script not found: $GDB_SCRIPT"

# ── Step 0: PS DDR initialization via XSDB ──────────────────────────────────
# CRITICAL: ZCU104 is in JTAG-boot mode. PS DDR is NOT initialized on power-up.
# Must run psu_init.tcl + bitstream download via XSDB before GDB can write DDR.
if [[ "$SKIP_DDR_INIT" != "1" ]]; then
    echo "[ddr-init] Running PS DDR init + PL program (cfg=$PHASE2_CFG)..."
    echo "[ddr-init] This flashes bitstream and initializes PS DDR via psu_init.tcl"
    if bash "${SCRIPT_DIR}/scripts/program_phase0b_bit.sh" --cfg "$PHASE2_CFG"; then
        ok "PS DDR init + PL program done"
        # After XSDB programming, give J-Link time to re-enumerate
        echo "[ddr-init] Waiting 5s for J-Link to stabilize after PL re-program..."
        sleep 5
    else
        warn "PS DDR init failed (rc=$?). Continuing anyway — DDR may not be ready."
        warn "Set SKIP_DDR_INIT=1 to suppress this step if FPGA already programmed."
    fi
else
    warn "SKIP_DDR_INIT=1: Skipping PS DDR init. FPGA must already be programmed."
fi

# Check and recover J-Link using the guarded flow
echo "[jlink] Running guarded J-Link recovery/precheck..."
if JLINK_HOST="$JLINK_HOST" JLINK_PORT="$JLINK_PORT" bash "${SCRIPT_DIR}/scripts/jlink_guard.sh"; then
    ok "J-Link guard passed"
else
    fail "J-Link guard failed at $JLINK_HOST:$JLINK_PORT"
fi

# Check payload size
PAYLOAD_SIZE=$(stat -c %s "$PAYLOAD_BIN")
ok "fw_payload.bin size: $PAYLOAD_SIZE bytes"

# Split payload into 4MB chunks
echo "[preflight] Splitting fw_payload.bin into chunks..."
mkdir -p "${CHUNK_DIR}"
rm -f "${CHUNK_DIR}"/chunk_*.bin
split -b 4194304 -d -a 2 --numeric-suffixes=0 --additional-suffix=.bin \
    "${PAYLOAD_BIN}" "${CHUNK_DIR}/chunk_"
CHUNK_COUNT="$(ls "${CHUNK_DIR}"/chunk_*.bin | wc -l)"
ok "${CHUNK_COUNT} chunks created in ${CHUNK_DIR}"

# Run the boot
echo ""
echo "[boot] Starting kernel boot + module load (${KERNEL_RUN_SECS}s)..."
echo ""

JLINK_HOST="$JLINK_HOST" \
JLINK_PORT="$JLINK_PORT" \
KERNEL_RUN_SECS="$KERNEL_RUN_SECS" \
PHASE2_CHUNK_DIR="$CHUNK_DIR" \
PHASE2_DTB="$DTB" \
"$GDB_BIN" -q -batch -x "$GDB_SCRIPT" 2>&1 | tee "/tmp/phase2_boot_$(date +%Y%m%d_%H%M%S).log"

GDB_RC=$?

echo ""
if [[ $GDB_RC -eq 0 ]]; then
    ok "Phase 2 boot GDB session completed (rc=0)"
    echo ""
    echo "Check /tmp/phase2_boot_*.log for:"
    echo "  ceva-bt52: bluetooth.ko OK"
    echo "  ceva-bt52: ceva_bt52.ko OK"
    echo "  registered as hci0"
else
    warn "GDB session exited with rc=$GDB_RC (check log for errors)"
fi
