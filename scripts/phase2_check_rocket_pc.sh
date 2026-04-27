#!/usr/bin/env bash
# phase2_check_rocket_pc.sh
#
# Phase 2: 启动 J-Link + 只读检查 Rocket PC
#   不加载 payload, 不修改 DDR, 不运行 linux_boot.gdb
#
# 前提:
#   Phase 1 已通过 (bitstream 已加载，PS-PL 隔离已移除)
#
# 成功标准:
#   J-Link 可连接 (IDCODE 正确)
#   PC 落在 BootROM 区域 (0x10000~0x20000)
#   BootROM 内容非零
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
GDB_SCRIPT="$SCRIPT_DIR/phase2_check_rocket_pc.gdb"

JLINK_HOST="${JLINK_HOST:-127.0.0.1}"
JLINK_PORT="${JLINK_PORT:-3333}"

if [[ ! -f "$GDB" ]]; then
    echo "Error: GDB not found: $GDB" >&2
    exit 1
fi
if [[ ! -f "$GDB_SCRIPT" ]]; then
    echo "Error: GDB script not found: $GDB_SCRIPT" >&2
    exit 1
fi

# --- Step 1: 先运行 J-Link 诊断 ---
echo "[Phase 2] === J-Link JTAG Chain Diagnostic ==="
bash "$SCRIPT_DIR/jlink_jtag_diag.sh" || true
echo ""

# --- Step 2: 启动 J-Link GDB Server ---
echo "[Phase 2] === Starting J-Link GDB Server ==="
JLINK_SERVER_LOG=/tmp/phase2_jlink_server.log

# 停止旧进程
powershell.exe -NoProfile -Command \
    'Stop-Process -Name JLinkGDBServerCL -ErrorAction SilentlyContinue; Start-Sleep 2' 2>/dev/null || true
sleep 2

# 停止 VMware USB 仲裁 (避免 J-Link 被抢占)
powershell.exe -NoProfile -Command \
    'Stop-Service VMUSBArbService -ErrorAction SilentlyContinue; Stop-Service VMAuthdService -ErrorAction SilentlyContinue' 2>/dev/null || true
sleep 1

# 启动 J-Link GDB Server
JLINK_BAT_CONTENT='"C:\Program Files\SEGGER\JLink\JLinkGDBServerCL.exe" -device RISC-V -if JTAG -speed 1000 -port 3333 -noir -nohalt -localhostonly 0 -noreset > C:\Users\Public\jlink_phase2.log 2>&1'
WIN_BAT=$(mktemp /mnt/c/Windows/Temp/jlink_phase2_XXXX.bat)
trap 'rm -f "$WIN_BAT"' EXIT
echo "@echo off" > "$WIN_BAT"
echo "$JLINK_BAT_CONTENT" >> "$WIN_BAT"
WIN_BAT_PATH=$(wslpath -w "$WIN_BAT")

powershell.exe -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c','$WIN_BAT_PATH' -WindowStyle Hidden" 2>/dev/null
echo "[Phase 2] J-Link GDB Server starting, waiting 6s..."
sleep 6

# --- Step 3: 检查 GDB Server 是否监听 ---
if nc -z -w 3 "${JLINK_HOST}" "${JLINK_PORT}" 2>/dev/null; then
    echo "[Phase 2] J-Link GDB Server reachable at ${JLINK_HOST}:${JLINK_PORT}"
else
    echo "[ERROR] J-Link GDB Server not reachable at ${JLINK_HOST}:${JLINK_PORT}" >&2
    echo "  检查 J-Link GDB Server 日志: C:\\Users\\Public\\jlink_phase2.log" >&2
    echo "  检查 J-Link USB 连接和驱动" >&2
    exit 1
fi

# --- Step 4: 运行只读 PC 检查 GDB 脚本 ---
echo ""
echo "[Phase 2] === Running read-only Rocket PC check ==="
echo ""

JLINK_HOST="${JLINK_HOST}" JLINK_PORT="${JLINK_PORT}" \
    "$GDB" -batch \
    -ex "set pagination off" \
    -x "$GDB_SCRIPT" \
    2>&1 | tee /tmp/phase2_rocket_pc.log

echo ""
echo "[Phase 2] Log saved to: /tmp/phase2_rocket_pc.log"
echo ""
echo "=== 请核对以下项目: ==="
echo "  1. J-Link IDCODE 正确? (RISC-V debug spec 0.13)"
echo "  2. PC 在 BootROM 区域 0x10000~0x20000?"
echo "  3. BootROM 内容非零?"
echo "  4. mcause=0 (无异常)?"
echo "  5. 如果 PC=0x80000000: payload 已在 DDR (跳过了?)"
echo ""
echo "如果以上全部正常 → 继续 Phase 3"
echo "如果 J-Link 无法连接 → 检查 Phase 1 bitstream 是否正确加载"
