#!/bin/bash
# Rebuild bitstream using Windows Vivado from WSL
# Converts all Linux paths to Windows UNC paths for Vivado
set -euo pipefail

VIVADO_BAT_WIN='E:\PRO_APP\xilinx\Vivado\2021.2\bin\vivado.bat'
WSL_UNC='\\wsl.localhost\Ubuntu-22.04'
WIN_DRIVE_PREFIX='Z:'

CONFIG_NAME="${CONFIG_NAME:-${CHIPYARD_ZCU104_CFG:-RocketZCU104LinuxBringupConfig}}"
BUILD_DIR="/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.${CONFIG_NAME}"
VIVADO_TCL="/root/chipyard/fpga/fpga-shells/xilinx/common/tcl/vivado.tcl"
MODEL="ZCU104FPGATestHarness"
BOARD="zcu104"
BIT_FILE="${BUILD_DIR}/obj/${MODEL}.bit"
BUILD_START_EPOCH=$(date +%s)
BUILD_BASENAME="chipyard.fpga.zcu104.${MODEL}.${CONFIG_NAME}"

# The original vsrcs.f file with Linux paths
ORIG_VSRCS="${BUILD_DIR}/${BUILD_BASENAME}.vsrcs.f"
if [[ ! -f "${ORIG_VSRCS}" ]]; then
  ORIG_VSRCS="${BUILD_DIR}/sim_files.common.f"
fi
if [[ ! -f "${ORIG_VSRCS}" ]]; then
  ORIG_VSRCS="${BUILD_DIR}/${BUILD_BASENAME}.all.f"
fi
# Converted copy with Windows UNC paths
WIN_VSRCS="${BUILD_DIR}/vsrcs_win.f"
TMP_WIN_VSRCS="${WIN_VSRCS}.tmp"

# IP vivado TCL files (from generated-src)
IP_TCLS=$(find "${BUILD_DIR}" -name '*.vivado.tcl' | sort)

echo "[1/4] Converting source file paths to Windows UNC format..."

if [[ ! -f "${ORIG_VSRCS}" ]]; then
  echo "[FAIL] Source manifest not found: ${BUILD_DIR}/${BUILD_BASENAME}.vsrcs.f, sim_files.common.f, or .all.f"
  exit 1
fi

# Convert all paths in the vsrcs.f file
sed "s|^/|${WIN_DRIVE_PREFIX}/|g" "$ORIG_VSRCS" > "$TMP_WIN_VSRCS"

# Preserve the vendor CEVA ordering for macro-carrying files. The generic
# Chipyard filelist flow sorts manifests, which moves user_defines_dm.v behind
# dependent sources such as rw_ble_core.v and breaks Vivado synthesis.
CEVA_ORDER_LIST="/root/chipyard/fpga/generated-src/ceva/rw_dm_top_rtl_files.list"
CEVA_WRAPPER_BASENAME="rw_dm_top_phase0b_real_wrapper.v"
CEVA_GEN_COLLATERAL_PREFIX="${WIN_DRIVE_PREFIX}${BUILD_DIR}/gen-collateral"

if [[ -f "${CEVA_ORDER_LIST}" && -f "${BUILD_DIR}/gen-collateral/${CEVA_WRAPPER_BASENAME}" ]]; then
  declare -A ceva_paths=()
  ordered_ceva_paths=()

  while IFS= read -r linux_path; do
    [[ -z "${linux_path}" ]] && continue
    ceva_basename="$(basename -- "${linux_path}")"
    win_path="${CEVA_GEN_COLLATERAL_PREFIX}/${ceva_basename}"
    if [[ -f "${BUILD_DIR}/gen-collateral/${ceva_basename}" ]]; then
      ceva_paths["${win_path}"]=1
      ordered_ceva_paths+=("${win_path}")
    fi
  done < "${CEVA_ORDER_LIST}"

  wrapper_win_path="${CEVA_GEN_COLLATERAL_PREFIX}/${CEVA_WRAPPER_BASENAME}"
  ceva_paths["${wrapper_win_path}"]=1
  ordered_ceva_paths+=("${wrapper_win_path}")

  : > "${WIN_VSRCS}"
  while IFS= read -r win_path; do
    [[ -n "${ceva_paths["${win_path}"]+set}" ]] && continue
    printf '%s\n' "${win_path}" >> "${WIN_VSRCS}"
  done < "${TMP_WIN_VSRCS}"
  printf '%s\n' "${ordered_ceva_paths[@]}" >> "${WIN_VSRCS}"
else
  mv "${TMP_WIN_VSRCS}" "${WIN_VSRCS}"
fi

rm -f "${TMP_WIN_VSRCS}"
echo "  Created $WIN_VSRCS ($(wc -l < "$WIN_VSRCS") files)"

# Convert IP TCL paths
WIN_IP_TCLS=""
for tcl in $IP_TCLS; do
  win_tcl="${WIN_DRIVE_PREFIX}${tcl}"
  WIN_IP_TCLS+="${win_tcl} "
done
WIN_IP_TCLS="${WIN_IP_TCLS% }"

echo "[2/4] Creating Windows wrapper..."

echo "[2a/4] Cleaning stale Vivado project cache..."
rm -rf "${BUILD_DIR}/${MODEL}.cache" "${BUILD_DIR}/.Xil"

WIN_BUILD_DIR="${WIN_DRIVE_PREFIX}${BUILD_DIR}"
WIN_VIVADO_TCL="${WIN_DRIVE_PREFIX}${VIVADO_TCL}"
WIN_VSRCS_PATH="${WIN_DRIVE_PREFIX}${BUILD_DIR}/vsrcs_win.f"

WIN_WRAPPER=$(mktemp /mnt/c/Windows/Temp/vivado_buildXXXXXX.cmd)
trap 'rm -f "$WIN_WRAPPER"' EXIT
WIN_WRAPPER_WIN=$(wslpath -w "$WIN_WRAPPER")

cat > "$WIN_WRAPPER" <<CMD
@echo off
REM Map WSL filesystem to a drive letter for CWD
net use Z: ${WSL_UNC} /persistent:no >nul 2>&1
pushd Z:${BUILD_DIR//\//\\}
"${VIVADO_BAT_WIN}" -nojournal -mode batch -source "${WIN_VIVADO_TCL}" -tclargs -top-module "${MODEL}" -F "${WIN_VSRCS_PATH}" -board "${BOARD}" -ip-vivado-tcls "${WIN_IP_TCLS}"
set EC=%ERRORLEVEL%
popd
net use Z: /delete /yes >nul 2>&1
exit /b %EC%
CMD

echo "[3/4] Launching Vivado (this will take 30-90 minutes)..."
echo "  Build dir: $BUILD_DIR"
echo "  Wrapper: $WIN_WRAPPER"
echo "  Vivado: $VIVADO_BAT_WIN"

# Run and tee output
cmd.exe /c "${WIN_WRAPPER_WIN}" 2>&1 | tee "${BUILD_DIR}/vivado_build.log"
EC=${PIPESTATUS[0]}

echo "[4/4] Build complete (exit code: $EC)"

if [[ $EC -ne 0 ]]; then
  echo "[FAIL] Vivado returned non-zero exit code"
  exit "$EC"
fi

if grep -qi '^ERROR:' "${BUILD_DIR}/vivado_build.log" 2>/dev/null; then
  echo "[FAIL] Vivado log contains ERROR lines"
  exit 1
fi

if [[ -f "${BIT_FILE}" ]]; then
  BIT_MTIME=$(stat -c %Y "${BIT_FILE}")
  if [[ $BIT_MTIME -lt $BUILD_START_EPOCH ]]; then
    echo "[FAIL] Bitstream timestamp did not advance during this build"
    ls -la "${BIT_FILE}"
    exit 1
  fi
  ls -la "${BIT_FILE}"
  echo "[OK] Bitstream generated successfully"
else
  echo "[FAIL] Bitstream not found!"
  exit 1
fi
