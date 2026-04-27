#!/usr/bin/env bash
# phase3_check_ddr_payload.sh
#
# Phase 3: 让 sd_loader 从 SD p2 加载 payload/DTB，只读验证 DDR
#   不修改任何内容，不跳 OpenSBI/Linux
#
# 前提:
#   Phase 1 通过 (bitstream 已加载)
#   Phase 2 通过 (Rocket 在 BootROM，J-Link 可连接)
#   SD 卡 p2 已有 manifest + fw_payload + DTB
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
GDB_SCRIPT="$SCRIPT_DIR/phase3_check_ddr_payload.gdb"

JLINK_HOST="${JLINK_HOST:-127.0.0.1}"
JLINK_PORT="${JLINK_PORT:-3333}"

# J-Link GDB Server 应已由 phase2 启动并持续运行
# 如果没有，先检查
if ! nc -z -w 3 "${JLINK_HOST}" "${JLINK_PORT}" 2>/dev/null; then
    echo "[ERROR] J-Link GDB Server not reachable at ${JLINK_HOST}:${JLINK_PORT}" >&2
    echo "  请先运行 Phase 2 确认 J-Link 连接正常" >&2
    exit 1
fi

echo "[Phase 3] J-Link Server reachable at ${JLINK_HOST}:${JLINK_PORT}"
echo "[Phase 3] Running DDR payload check (READ-ONLY)..."
echo ""

JLINK_HOST="${JLINK_HOST}" JLINK_PORT="${JLINK_PORT}" \
    "$GDB" -batch \
    -x "$GDB_SCRIPT" \
    2>&1 | tee /tmp/phase3_ddr_check.log

echo ""
echo "[Phase 3] Log saved to: /tmp/phase3_ddr_check.log"
echo ""
echo "=== 判断标准: ==="
echo "  PASS: 0x80000000 非零 + 0x84000000 = 0xD00DFEED"
echo "  FAIL: 任一地址全零 → sd_loader 未完成加载"
echo ""
echo "  PASS 时 → 继续 Phase 4 (让 Rocket 跳入 OpenSBI/Linux)"
echo "  FAIL 时 → 检查 SD p2 内容是否正确"
echo ""
echo "  注意: fw_payload 约 50MB, sd_loader 读取需要一定时间"
echo "        如果 15s 后仍为 0，可增加等待时间重试"
