#!/usr/bin/env bash
set -euo pipefail

# phase0b_start_jlink.sh — 启动 Phase0b 调试使用的 J-Link GDB Server
# 用法:
#   bash scripts/phase0b_start_jlink.sh
#
# 行为:
#   1. 先尝试直接启动 J-Link
#   2. 若命中已知的 "core could not be halted" 状态，则自动补一轮
#      Phase0b 完整 PS+PL 初始化，再重试一次

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LOG=/tmp/jlink_gdbserver.log

try_start() {
	bash "$SCRIPT_DIR/start_jlink_server.sh"
}

if try_start; then
	exit 0
fi

if [[ -f "$LOG" ]] && grep -q "Timeout while waiting for core to halt after reset and halt request" "$LOG"; then
	echo "[phase0b] 检测到已知 J-Link halt 超时状态，自动补做一轮 Phase0b 完整初始化后重试..."
	bash "$SCRIPT_DIR/phase0b_full_init.sh"
	echo "[phase0b] 重新启动 J-Link..."
	exec bash "$SCRIPT_DIR/start_jlink_server.sh"
fi

exit 1