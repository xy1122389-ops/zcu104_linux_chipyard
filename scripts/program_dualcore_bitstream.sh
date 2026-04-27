#!/usr/bin/env bash
set -euo pipefail

# 双核 Bitstream 烧录脚本
# 通过 XSDB 和 Vivado Hardware Server 烧录到 ZCU104 PL

BITSTREAM_LINUX="/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104DualCoreLinuxBringupConfig/obj/ZCU104FPGATestHarness.bit"

if [ ! -f "$BITSTREAM_LINUX" ]; then
    echo "ERROR: Bitstream not found: $BITSTREAM_LINUX"
    exit 1
fi

echo "=== ZCU104 Dual-Core Bitstream Programming ==="
echo "Bitstream: $BITSTREAM_LINUX"
echo "Size: $(du -h "$BITSTREAM_LINUX" | cut -f1)"
echo "SHA256: $(sha256sum "$BITSTREAM_LINUX" | cut -d' ' -f1)"
echo ""

# 转换到 Windows 路径 (Z: drive mapping)
# /root → Z:\root
BITSTREAM_WIN="Z:${BITSTREAM_LINUX}"

echo "Windows path: $BITSTREAM_WIN"
echo ""
echo "=== Launching XSDB for bitstream programming ==="

# 导出环境变量给 PowerShell 脚本
export CHIPYARD_BIT_WIN="$BITSTREAM_WIN"

# 通过 PowerShell 调用 XSDB
powershell.exe -NoProfile -Command "
\$env:CHIPYARD_BIT_WIN = '$BITSTREAM_WIN'
cd C:\Users\Public
E:\PRO_APP\xilinx\Vivado\2021.2\bin\xsdb.bat C:\Users\Public\xsdb_program_dualcore_bit.tcl 2>&1
"

echo ""
echo "=== Bitstream programming completed ==="
