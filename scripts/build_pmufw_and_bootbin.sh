#!/usr/bin/env bash
# build_pmufw_and_bootbin.sh
# Step 1: Generate XSA from existing Vivado project (batch mode)
# Step 2: Build PMUFW using XSCT
# Step 3: Rebuild BOOT.BIN with PMUFW included
# Step 4: Copy BOOT.BIN to ~/zcu104_selfboot_files/ and runs/golden_fedora_pio_1800s/
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR="${SCRIPT_DIR}/.."
VIVADO_BAT="/mnt/e/PRO_APP/xilinx/Vivado/2021.2/bin/vivado.bat"
XSDB_BAT="/mnt/e/PRO_APP/xilinx/Vivado/2021.2/bin/xsdb.bat"

# Windows-side temp paths
WIN_XSA="C:\\tmp\\pmufw_build\\zcu104.xsa"
WIN_PMUFW_ELF="C:\\tmp\\pmufw_build\\pmufw.elf"
WIN_TMPDIR="C:\\tmp\\pmufw_build"

# Linux-side paths
LINUX_PMUFW_ELF="/tmp/pmufw_build/pmufw.elf"
GEN_XSA_TCL="${SCRIPT_DIR}/gen_xsa_for_pmufw.tcl"
BUILD_PMUFW_TCL="${SCRIPT_DIR}/build_pmufw_xsct.tcl"
BIF_FILE="/tmp/fsbl_build/bootbin/zcu104_with_pmufw.bif"
NEW_BOOT_BIN="/tmp/BOOT_with_pmufw.BIN"

echo "=== Step 1: Generate XSA from Vivado project ==="
# Create Windows temp dir
WIN_TMPDIR_WIN="${WIN_TMPDIR}"
powershell.exe -Command "New-Item -ItemType Directory -Force -Path '${WIN_TMPDIR}' | Out-Null"

# Vivado batch mode to generate XSA
WIN_TCL=$(wslpath -w "${GEN_XSA_TCL}")
WIN_LOG="C:\\tmp\\pmufw_build\\gen_xsa.log"

# Use cmd.exe to run Vivado batch
WIN_WRAPPER=$(mktemp /mnt/c/Windows/Temp/vivado_xsaXXXX.cmd)
WIN_VIVADO=$(wslpath -w "${VIVADO_BAT}")
cat > "${WIN_WRAPPER}" <<EOF
@echo off
call "${WIN_VIVADO}" -mode batch -source "${WIN_TCL}" -nojournal -nolog
EOF
chmod +x "${WIN_WRAPPER}"
echo "[step1] Running Vivado batch to generate XSA..."
cmd.exe /C "$(wslpath -w "${WIN_WRAPPER}")" 2>&1 | tee /tmp/pmufw_build_gen_xsa.log || true

if [[ ! -f "/mnt/c/tmp/pmufw_build/zcu104.xsa" ]] && [[ ! -f "$(wslpath -u "${WIN_XSA}" 2>/dev/null || echo /nonexistent)" ]]; then
    echo "[WARN] XSA generation may have failed - check /tmp/pmufw_build_gen_xsa.log"
    # Try to find XSA
    WIN_XSA_LINUX=$(wslpath -u "${WIN_XSA}" 2>/dev/null || true)
    if [[ ! -f "${WIN_XSA_LINUX}" ]]; then
        echo "[ERROR] XSA not found at: ${WIN_XSA_LINUX}"
        exit 1
    fi
fi
echo "[step1] XSA generated: ${WIN_XSA}"

echo ""
echo "=== Step 2: Build PMUFW using XSCT ==="
WIN_PMUFW_TCL=$(wslpath -w "${BUILD_PMUFW_TCL}")
WIN_XSDB=$(wslpath -w "${XSDB_BAT}")
WIN_WRAPPER2=$(mktemp /mnt/c/Windows/Temp/xsct_pmufwXXXX.cmd)
cat > "${WIN_WRAPPER2}" <<EOF
@echo off
call "${WIN_XSDB}" "${WIN_PMUFW_TCL}"
EOF
chmod +x "${WIN_WRAPPER2}"
echo "[step2] Running XSCT to build PMUFW..."
cmd.exe /C "$(wslpath -w "${WIN_WRAPPER2}")" 2>&1 | tee /tmp/pmufw_build_xsct.log || true

# Check PMUFW output
WIN_PMUFW_ELF_LINUX=$(wslpath -u "${WIN_PMUFW_ELF}" 2>/dev/null || echo "/mnt/c/tmp/pmufw_build/pmufw.elf")
if [[ ! -f "${WIN_PMUFW_ELF_LINUX}" ]]; then
    echo "[ERROR] pmufw.elf not found at: ${WIN_PMUFW_ELF_LINUX}"
    echo "[ERROR] Check /tmp/pmufw_build_xsct.log for details"
    exit 1
fi
mkdir -p /tmp/pmufw_build
cp "${WIN_PMUFW_ELF_LINUX}" "${LINUX_PMUFW_ELF}"
echo "[step2] pmufw.elf -> ${LINUX_PMUFW_ELF} ($(stat -c%s "${LINUX_PMUFW_ELF}") bytes)"

echo ""
echo "=== Step 3: Rebuild BOOT.BIN with PMUFW ==="
mkdir -p "$(dirname "${BIF_FILE}")"
cat > "${BIF_FILE}" <<EOF
the_ROM_image:
{
    [pmufw_image] /tmp/pmufw_build/pmufw.elf
    [bootloader, destination_cpu=a53-0] /tmp/embeddedsw/lib/sw_apps/zynqmp_fsbl/src/ron_a53_fsbl.elf
    [destination_device=pl] /root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/obj/ZCU104FPGATestHarness.bit
    [destination_cpu=a53-0, exception_level=el-3] /tmp/fsbl_build/arm_stub/arm_stub.elf
}
EOF

echo "[step3] BIF:"
cat "${BIF_FILE}"
echo ""

bootgen -image "${BIF_FILE}" -arch zynqmp -o "${NEW_BOOT_BIN}" -w on
if [[ ! -f "${NEW_BOOT_BIN}" ]]; then
    echo "[ERROR] bootgen failed, BOOT.BIN not created"
    exit 1
fi
echo "[step3] BOOT.BIN: ${NEW_BOOT_BIN} ($(stat -c%s "${NEW_BOOT_BIN}") bytes)"
sha256sum "${NEW_BOOT_BIN}"

echo ""
echo "=== Step 4: Copy to output directories ==="
cp "${NEW_BOOT_BIN}" /root/zcu104_selfboot_files/BOOT.BIN
cp "${NEW_BOOT_BIN}" /root/chipyard/fpga/runs/golden_fedora_pio_1800s/BOOT.BIN
echo "[step4] Copied to ~/zcu104_selfboot_files/BOOT.BIN"
echo "[step4] Copied to runs/golden_fedora_pio_1800s/BOOT.BIN"

echo ""
echo "=== BOOT.BIN with PMUFW build complete ==="
echo "Next: copy /root/zcu104_selfboot_files/BOOT.BIN to SD card p1 (replace /boot/BOOT.BIN)"
bootgen -read "${NEW_BOOT_BIN}" 2>&1 | grep -E 'IMAGE HEADER|pmufw|fsbl|bit|arm_stub' | head -20
