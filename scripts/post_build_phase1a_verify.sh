#!/bin/bash
# post_build_phase1a_verify.sh
# Complete workflow after Vivado rebuild:
# 1. Wait for new bitstream
# 2. Flash to ZCU104 via XSDB
# 3. Start J-Link GDB Server
# 4. Run Phase 1A EM MMIO verification
# 5. If PASS, run Phase 2 Linux boot
#
# Usage: bash scripts/post_build_phase1a_verify.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FPGA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
export PATH="/root/chipyard/.oclaw-env/bin:/root/chipyard/.oclaw-env/riscv-tools/bin:$PATH"

CONFIG_NAME="RocketZCU104Phase0bConfig"
BUILD_DIR="${FPGA_DIR}/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.${CONFIG_NAME}"
BIT_FILE="${BUILD_DIR}/obj/ZCU104FPGATestHarness.bit"

echo "================================================================"
echo " Post-Build Phase 1A Verification Workflow"
echo "================================================================"

# Step 1: Check for new bitstream
echo "[Step 1] Checking for new bitstream..."
if [[ ! -f "$BIT_FILE" ]]; then
    echo "ERROR: Bitstream not found: $BIT_FILE"
    exit 1
fi
BIT_DATE=$(stat -c '%y' "$BIT_FILE")
echo "  Bitstream: $(ls -lh "$BIT_FILE" | awk '{print $5, $6, $7, $8}')"

# Wait for Vivado to finish if still running
MAX_WAIT=7200  # 2 hours
WAIT_COUNT=0
while powershell.exe -NoProfile -Command 'if (Get-Process -Name "vivado" -ErrorAction SilentlyContinue) {exit 0} else {exit 1}' 2>/dev/null; do
    echo "  [$(date '+%H:%M:%S')] Vivado still running, waiting 60s..."
    sleep 60
    WAIT_COUNT=$((WAIT_COUNT + 60))
    if (( WAIT_COUNT > MAX_WAIT )); then
        echo "ERROR: Vivado timed out after ${MAX_WAIT}s"
        exit 1
    fi
done
echo "  Vivado completed."

# Verify bitstream was actually updated (not old)
BIT_EPOCH=$(stat -c '%Y' "$BIT_FILE")
START_EPOCH=$(stat -c '%Y' "${BUILD_DIR}/vivado.log")
if (( BIT_EPOCH < START_EPOCH )); then
    echo "ERROR: Bitstream is older than vivado.log! Build may have failed."
    echo "  Check ${BUILD_DIR}/vivado.log for errors"
    exit 1
fi
echo "  New bitstream confirmed: $(date -d @${BIT_EPOCH})"
ls -lh "$BIT_FILE"

# Step 2: Flash bitstream via XSDB
echo ""
echo "[Step 2] Flashing bitstream to ZCU104..."
if ! bash "${SCRIPT_DIR}/program_phase0b_bit.sh" 2>&1; then
    echo "ERROR: Flash failed"
    exit 1
fi
echo "  Flash OK"

# Step 3: Start J-Link GDB Server
echo ""
echo "[Step 3] Starting J-Link GDB Server..."
sleep 3  # Give board time to come up after flash

MAX_JLINK_RETRIES=5
for i in $(seq 1 $MAX_JLINK_RETRIES); do
    if bash "${SCRIPT_DIR}/start_jlink_server.sh" 2>&1; then
        echo "  J-Link started OK"
        break
    fi
    echo "  Retry ${i}/${MAX_JLINK_RETRIES}..."
    sleep 5
    if (( i == MAX_JLINK_RETRIES )); then
        echo "ERROR: J-Link failed to start after ${MAX_JLINK_RETRIES} retries"
        echo "  Possible causes:"
        echo "    - J-Link USB cable disconnected"
        echo "    - J-Link GDB Server process needs to be killed on Windows"
        echo "  Fix: reconnect USB, then run: bash scripts/start_jlink_server.sh"
        exit 1
    fi
done

# Verify J-Link connection
if ! nc -z -w 3 127.0.0.1 3333; then
    echo "ERROR: J-Link port 3333 not responding"
    exit 1
fi
echo "  J-Link OK (port 3333 open)"

# Step 4: Quick sanity check
echo ""
echo "[Step 4] Quick connection sanity check..."
SANITY_OUT=$(timeout 20 riscv64-unknown-elf-gdb -q -batch \
    -ex "set remotetimeout 15" \
    -ex "target remote 127.0.0.1:3333" \
    -ex "monitor halt" \
    -ex "p/x \$pc" \
    -ex "detach" 2>&1)
if echo "$SANITY_OUT" | grep -q '0x'; then
    PC=$(echo "$SANITY_OUT" | grep -oE '0x[0-9a-fA-F]+' | tail -1)
    echo "  CPU halted at PC=$PC - J-Link connection OK"
else
    echo "ERROR: GDB sanity check failed:"
    echo "$SANITY_OUT"
    exit 1
fi

# Step 5: Run Phase 1A EM MMIO verification
echo ""
echo "[Step 5] Running Phase 1A: CPU EM MMIO Window Verification..."
PHASE1A_OUT=$(timeout 120 riscv64-unknown-elf-gdb -q -batch \
    -x "${SCRIPT_DIR}/ceva_phase1a_jlink_em_mmio.gdb" 2>&1)
echo "$PHASE1A_OUT"

if echo "$PHASE1A_OUT" | grep -q "VERDICT: PASS"; then
    echo ""
    echo "  Phase 1A: PASS"
elif echo "$PHASE1A_OUT" | grep -q "VERDICT: FAIL"; then
    echo ""
    echo "  Phase 1A: FAIL"
    echo "$PHASE1A_OUT" | grep "VERDICT\|FAIL\|MISMATCH"
    exit 1
else
    echo "  Phase 1A: UNKNOWN (no VERDICT found)"
    echo "$PHASE1A_OUT" | tail -20
    exit 1
fi

# Step 6: Phase 2 Linux boot (optional, if Phase 1A PASS)
echo ""
echo "[Step 6] Running Phase 2: Linux Boot + CEVA BT Driver Verification..."
KERNEL_RUN_SECS="${KERNEL_RUN_SECS:-180}" bash "${FPGA_DIR}/run_phase2_ceva_bt_linux.sh"

echo ""
echo "================================================================"
echo " All phases complete!"
echo "================================================================"
