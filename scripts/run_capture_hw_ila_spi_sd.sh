#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
TCL_SCRIPT="${SCRIPT_DIR}/capture_hw_ila_spi_sd.tcl"
OBJ_DIR="${FPGA_DIR}/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/obj/spi_sd_ila"
LTX_FILE="${OBJ_DIR}/spi_sd_ila.ltx"
OUT_DIR_DEFAULT="${FPGA_DIR}/logs/spi_sd_ila_captures"
VIVADO_BAT_DEFAULT='/mnt/e/PRO_APP/xilinx/Vivado/2021.2/bin/vivado.bat'

usage() {
  cat <<'EOF'
Usage:
  run_capture_hw_ila_spi_sd.sh [--tag TAG] [--out-dir DIR] [--timeout-mins N]

Examples:
  bash scripts/run_capture_hw_ila_spi_sd.sh --tag phase1_spi_sd_capture1
  bash scripts/run_capture_hw_ila_spi_sd.sh --timeout-mins 20
EOF
}

TAG="spi_sd_ila_$(date +%Y%m%d_%H%M%S)"
OUT_DIR="$OUT_DIR_DEFAULT"
TIMEOUT_MINS="15"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ $# -ge 2 ]] || { echo "Error: --tag requires an argument" >&2; exit 1; }
      TAG="$2"
      shift 2
      ;;
    --out-dir)
      [[ $# -ge 2 ]] || { echo "Error: --out-dir requires an argument" >&2; exit 1; }
      OUT_DIR="$2"
      shift 2
      ;;
    --timeout-mins)
      [[ $# -ge 2 ]] || { echo "Error: --timeout-mins requires an argument" >&2; exit 1; }
      TIMEOUT_MINS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$OUT_DIR"

if [[ ! -f "$TCL_SCRIPT" ]]; then
  echo "Error: missing Tcl script: $TCL_SCRIPT" >&2
  exit 1
fi
if [[ ! -f "$LTX_FILE" ]]; then
  echo "Error: missing ltx file: $LTX_FILE" >&2
  exit 1
fi

VIVADO_BAT="${VIVADO_BAT:-$VIVADO_BAT_DEFAULT}"
if [[ ! -f "$VIVADO_BAT" ]]; then
  echo "Error: Vivado batch launcher not found: $VIVADO_BAT" >&2
  exit 1
fi

if [[ ! -d /mnt/c/Windows/Temp ]]; then
  echo "Error: /mnt/c/Windows/Temp not found" >&2
  exit 1
fi

OUT_BASE="${OUT_DIR}/${TAG}"
WIN_WRAPPER=$(mktemp /mnt/c/Windows/Temp/vivado_spi_sd_captureXXXX.cmd)
trap 'rm -f "$WIN_WRAPPER"' EXIT

WIN_WRAPPER_CMD=$(wslpath -w "$WIN_WRAPPER")
WIN_VIVADO_BAT=$(wslpath -w "$VIVADO_BAT")
WIN_REPO_DIR='\\wsl$\Ubuntu-22.04\root\chipyard\fpga'
WIN_TCL=$(wslpath -w "$TCL_SCRIPT")

cat > "$WIN_WRAPPER" <<CMD
@echo off
pushd "$WIN_REPO_DIR" || exit /b 1
call "$WIN_VIVADO_BAT" -mode batch -source "$WIN_TCL" -tclargs "$LTX_FILE" "$OUT_BASE" "$TIMEOUT_MINS"
set RET=%ERRORLEVEL%
popd
exit /b %RET%
CMD

echo "[info] Capturing SPI-SD ILA"
echo "[info] LTX      : $LTX_FILE"
echo "[info] OUT_BASE : $OUT_BASE"
echo "[info] TIMEOUT  : ${TIMEOUT_MINS} min"

exec cmd.exe /c "$WIN_WRAPPER_CMD"