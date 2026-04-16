#!/bin/bash
# Incremental rebuild of ZCU104 bitstream after BootROM change
# Runs Vivado on Windows via WSL

set -e

CONFIG="chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig"
BUILD_DIR="/root/chipyard/fpga/generated-src/$CONFIG"
OBJ_DIR="$BUILD_DIR/obj"
TCL_SCRIPT="/root/chipyard/fpga/scripts/rebuild_incremental.tcl"
VIVADO_BAT="/mnt/e/PRO_APP/xilinx/Vivado/2021.2/bin/vivado.bat"

# Backup current bitstream
if [ -f "$OBJ_DIR/ZCU104FPGATestHarness.bit" ]; then
    BACKUP="$OBJ_DIR/ZCU104FPGATestHarness.bit.bak.pre_autojump_$(date +%Y%m%d_%H%M%S)"
    cp "$OBJ_DIR/ZCU104FPGATestHarness.bit" "$BACKUP"
    echo "Backed up bitstream to: $BACKUP"
fi

# Convert paths for Windows
WIN_TCL=$(wslpath -w "$TCL_SCRIPT")
WIN_BUILD_DIR=$(wslpath -w "$BUILD_DIR")

echo "=== Launching Vivado Incremental Rebuild ==="
echo "TCL Script: $WIN_TCL"
echo "Build Dir:  $WIN_BUILD_DIR"
echo "Started:    $(date)"
echo ""

# Run Vivado from the build directory
cd "$BUILD_DIR"

# Use cmd.exe to call vivado.bat
cmd.exe /c "cd /d $WIN_BUILD_DIR && E:\\PRO_APP\\xilinx\\Vivado\\2021.2\\bin\\vivado.bat -nojournal -mode batch -source $WIN_TCL" 2>&1 | tee "$BUILD_DIR/vivado_incremental_rebuild.log"

echo ""
echo "=== Rebuild Complete ==="
echo "Finished:   $(date)"

if [ -f "$OBJ_DIR/ZCU104FPGATestHarness.bit" ]; then
    ls -la "$OBJ_DIR/ZCU104FPGATestHarness.bit"
    echo "SUCCESS: New bitstream generated"
else
    echo "ERROR: Bitstream not found!"
    exit 1
fi
