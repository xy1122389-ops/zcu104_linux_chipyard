#!/usr/bin/env bash
# phase4_check_opensbi_linux.sh
#
# Phase 4: 让 Rocket 跳入 OpenSBI/Linux，通过 PC 和 klog 验证
#   不 restore payload，payload 由 sd_loader 加载 (Phase 3 已通过)
#
# 用法:
#   bash scripts/phase4_check_opensbi_linux.sh
#   PHASE4_RUN_SECS=120 bash scripts/phase4_check_opensbi_linux.sh
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
GDB_SCRIPT="$SCRIPT_DIR/phase4_check_opensbi_linux.gdb"

JLINK_HOST="${JLINK_HOST:-127.0.0.1}"
JLINK_PORT="${JLINK_PORT:-3333}"
PHASE4_RUN_SECS="${PHASE4_RUN_SECS:-60}"

if ! nc -z -w 3 "${JLINK_HOST}" "${JLINK_PORT}" 2>/dev/null; then
    echo "[ERROR] J-Link GDB Server not reachable at ${JLINK_HOST}:${JLINK_PORT}" >&2
    exit 1
fi

echo "[Phase 4] J-Link Server reachable at ${JLINK_HOST}:${JLINK_PORT}"
echo "[Phase 4] Linux run time: ${PHASE4_RUN_SECS}s"
echo "[Phase 4] Running OpenSBI/Linux entry check..."
echo ""

JLINK_HOST="${JLINK_HOST}" JLINK_PORT="${JLINK_PORT}" \
PHASE4_RUN_SECS="${PHASE4_RUN_SECS}" \
    "$GDB" -batch \
    -x "$GDB_SCRIPT" \
    2>&1 | tee /tmp/phase4_linux_check.log

echo ""
echo "[Phase 4] Log saved to: /tmp/phase4_linux_check.log"
echo ""
echo "=== Phase 4 判断标准: ==="
echo "  PASS: PC 在 kernel VA 范围 + klog 有 'Linux version'"
echo "  PARTIAL: PC 在 DDR 但 stage_mark=0 → Linux 启动中但未到 userspace"
echo "  FAIL: PC 仍在 BootROM → sd_loader 未跳入 DDR"
echo ""
echo "  PASS → Phase 5: SW6 切到 SD boot，全自动测试"
