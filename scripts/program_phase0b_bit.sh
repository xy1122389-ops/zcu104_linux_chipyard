#!/usr/bin/env bash
# program_phase0b_bit.sh — ZCU104 PS+PL 完整初始化
#
# 默认烧录 RocketZCU104Phase0bConfig，也支持 --cfg 做快速 A/B 对照。
#
# 用法:
#   bash scripts/program_phase0b_bit.sh
#   bash scripts/program_phase0b_bit.sh --cfg RocketZCU104JLinkDiagConfig
#
# 前提:
#   1. ZCU104 已上电，USB JTAG 已连
#   2. Vivado hw_server 可被 XSDB 访问 (127.0.0.1:3121)
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DEFAULT_CFG="RocketZCU104Phase0bConfig"
CFG="$DEFAULT_CFG"

usage() {
    cat <<'EOF'
Usage:
  bash scripts/program_phase0b_bit.sh
  bash scripts/program_phase0b_bit.sh --cfg RocketZCU104JLinkDiagConfig

Notes:
  - Default cfg: RocketZCU104Phase0bConfig
  - This runs full PS init + PL program + PS-PL release via run_ps_ddr_init.sh
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cfg)
            [[ $# -ge 2 ]] || { echo "ERROR: --cfg requires a value" >&2; usage; exit 2; }
            CFG="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

BIT_LINUX="${SCRIPT_DIR}/../generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.${CFG}/obj/ZCU104FPGATestHarness.bit"

if [[ ! -f "$BIT_LINUX" ]]; then
    echo "ERROR: bitstream not found at $BIT_LINUX" >&2
    echo "       Run: make SUB_PROJECT=zcu104 CONFIG=${CFG} bitstream" >&2
    exit 1
fi

echo "=== ZCU104: PS+PL 完整初始化 ==="
echo "Config   : $CFG"
echo "Bitstream: $BIT_LINUX"
echo ""

exec bash "${SCRIPT_DIR}/run_ps_ddr_init.sh" --cfg "$CFG"
