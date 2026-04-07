#!/usr/bin/env bash
# dump_klog.sh — Halt kernel, dump ring buffer, show dmesg, check dcsr fix
#
# Usage: ./scripts/dump_klog.sh [output_file]
set -euo pipefail
export PATH="/root/chipyard/.oclaw-env/riscv-tools/bin:$PATH"

OUT="${1:-/tmp/klog_latest.bin}"
KLOG_PA=0x830e7108
KLOG_SZ=0x20000
OLD_STUCK_PC="8061c820"

# Auto-detect Windows host IP (WSL2 gateway)
JLINK_HOST=$(ip route | awk '/default/ {print $3; exit}')
JLINK_HOST=${JLINK_HOST:-172.19.128.1}
echo "[dump_klog] Connecting to J-Link at ${JLINK_HOST}:2331, halting kernel..."

OUTPUT=$(timeout 30 riscv64-unknown-elf-gdb -batch \
  -ex "set remotetimeout 15" \
  -ex "target remote ${JLINK_HOST}:2331" \
  -ex "monitor halt" \
  -ex "echo --- Kernel state ---\n" \
  -ex "info reg pc ra sp" \
  -ex "monitor ReadCSR 0x7b0" \
  -ex "dump binary memory $OUT $KLOG_PA ($KLOG_PA + $KLOG_SZ)" \
  -ex "echo [dumped] $OUT\n" \
  -ex "detach" \
  -ex "quit" 2>&1)

echo "$OUTPUT"

echo ""
echo "=== Verification ==="
if echo "$OUTPUT" | grep -q "$OLD_STUCK_PC"; then
  echo "[FAIL] Kernel still stuck at stack_depot_early_init (0xffffffff$OLD_STUCK_PC)"
  echo "       dcsr ebreak fix did NOT resolve the halt."
else
  echo "[INFO] PC is NOT at old stuck address. dcsr fix may have worked!"
fi

echo ""
echo "=== Kernel dmesg (first 200 lines) ==="
strings "$OUT" | head -200
