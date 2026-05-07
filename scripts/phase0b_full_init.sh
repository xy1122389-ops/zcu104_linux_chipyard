#!/usr/bin/env bash
set -euo pipefail

# phase0b_full_init.sh — 固定执行 Phase0b 的完整 PS+PL 初始化
# 用法:
#   bash scripts/phase0b_full_init.sh

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

exec bash "$SCRIPT_DIR/program_phase0b_bit.sh" --cfg RocketZCU104Phase0bConfig