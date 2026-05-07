#!/usr/bin/env bash
# read_ceva_version.sh — 通过 J-Link GDB 读 CEVA DM VERSION 寄存器
#
# 目标: 读 *(uint32_t*)0x65000004，期望返回 0x0B000500
#
# 前提:
#   1. Phase0b bitstream 已下载到 ZCU104 PL
#   2. J-Link GDB Server 已启动 (bash scripts/start_jlink_server.sh)
#   3. J-Link 通过 J55 连接到 ZCU104 JTAG (PMOD0 G6/H6/J6/J7)
#
# 用法:
#   cd /root/chipyard/fpga
#   bash scripts/read_ceva_version.sh
#
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
JLINK_HOST=127.0.0.1
JLINK_PORT=3333
CEVA_VERSION_ADDR=0x65000004
EXPECTED=0x0B000500

echo "=== CEVA DM VERSION 读取测试 ==="
echo "地址: $CEVA_VERSION_ADDR"
echo "期望: $EXPECTED"
echo ""

# 验证 GDB server 可达
if ! nc -z -w 3 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
    echo "[info] J-Link GDB Server 未监听 $JLINK_HOST:$JLINK_PORT，自动启动..."
    bash "$SCRIPT_DIR/start_jlink_server.sh"
fi

if ! nc -z -w 3 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
    echo "ERROR: J-Link GDB Server 仍未监听 $JLINK_HOST:$JLINK_PORT"
    echo "       请先检查: bash scripts/start_jlink_server.sh"
    exit 1
fi

RESULT=$(timeout 30 "$GDB" -q -batch \
    -ex "set remotetimeout 15" \
    -ex "target remote $JLINK_HOST:$JLINK_PORT" \
    -ex "monitor halt" \
    -ex "x/1wx $CEVA_VERSION_ADDR" \
    -ex "monitor go" \
    -ex "detach" \
    2>&1)

echo "$RESULT"

# 解析结果
RAW=$(echo "$RESULT" | grep "$CEVA_VERSION_ADDR:" | head -1 | awk '{print $2}')

if [[ "$RAW" == "0x0b000500" || "$RAW" == "0x0B000500" ]]; then
    echo ""
    echo "✓ PASS: 0x65000004 = 0x0B000500 (CEVA DM VERSION 正确)"
    exit 0
else
    echo ""
    echo "✗ FAIL: 0x65000004 = ${RAW:-<unreadable>}"
    echo ""
    echo "失败诊断:"
    echo "  0x00000000 → bitstream 未下载 / clock/reset 未拉起"
    echo "  0xFFFFFFFF → 地址未映射 / TL fabric 断路"
    echo "  0x0B000600 → 读到 BT VERSION，haddr decode 错"
    echo "  0x0B001100 → 读到 BLE VERSION，haddr decode 错"
    echo "  bus hang   → hready/hresp 错 / TLFragmenter 问题"
    exit 1
fi
