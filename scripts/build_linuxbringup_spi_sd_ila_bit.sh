#!/usr/bin/env bash
set -euo pipefail

FPGA_DIR=/root/chipyard/fpga
LONG_NAME=chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig
OBJ_DIR="$FPGA_DIR/generated-src/$LONG_NAME/obj"

IN_DCP=${1:-$OBJ_DIR/post_synth.dcp}
OUT_DIR=${2:-$OBJ_DIR/spi_sd_ila}
TCL_SCRIPT=${TCL_SCRIPT:-$FPGA_DIR/scripts/insert_ila_spi_sd_zcu104.tcl}
VIVADO_BAT=${VIVADO_BAT:-/mnt/e/PRO_APP/xilinx/Vivado/2021.2/bin/vivado.bat}

if [[ ! -f "$IN_DCP" ]]; then
  echo "Error: input DCP not found: $IN_DCP" >&2
  exit 2
fi

if [[ ! -f "$TCL_SCRIPT" ]]; then
  echo "Error: Tcl script not found: $TCL_SCRIPT" >&2
  exit 2
fi

if [[ ! -f "$VIVADO_BAT" ]]; then
  echo "Error: Vivado batch launcher not found: $VIVADO_BAT" >&2
  exit 2
fi

if [[ ! -d /mnt/c/Windows/Temp ]]; then
  echo "Error: /mnt/c/Windows/Temp not found; cannot create Windows wrapper." >&2
  exit 3
fi

mkdir -p "$OUT_DIR"

STAGE_DIR=$(mktemp -d /mnt/c/Windows/Temp/spi_sd_ila_jobXXXX)
STAGE_IN_DCP="$STAGE_DIR/$(basename "$IN_DCP")"
STAGE_TCL_SCRIPT="$STAGE_DIR/$(basename "$TCL_SCRIPT")"
STAGE_OUT_DIR="$STAGE_DIR/out"

cp -f "$IN_DCP" "$STAGE_IN_DCP"
cp -f "$TCL_SCRIPT" "$STAGE_TCL_SCRIPT"
mkdir -p "$STAGE_OUT_DIR"

WIN_VIVADO_BAT=$(wslpath -w "$VIVADO_BAT")
WIN_FPGA_DIR=$(wslpath -w "$FPGA_DIR")
WIN_TCL_SCRIPT=$(wslpath -w "$STAGE_TCL_SCRIPT")
WIN_IN_DCP=$(wslpath -w "$STAGE_IN_DCP")
WIN_OUT_DIR=$(wslpath -w "$STAGE_OUT_DIR")

WIN_WRAPPER=$(mktemp /mnt/c/Windows/Temp/vivado_spi_sd_ilaXXXX.cmd)
trap 'rm -f "$WIN_WRAPPER"' EXIT
WIN_WRAPPER_CMD=$(wslpath -w "$WIN_WRAPPER")

cat > "$WIN_WRAPPER" <<CMD
@echo off
pushd "$WIN_FPGA_DIR"
call "$WIN_VIVADO_BAT" -nojournal -mode batch -source "$WIN_TCL_SCRIPT" -tclargs "$WIN_IN_DCP" "$WIN_OUT_DIR"
set EC=%ERRORLEVEL%
popd
exit /b %EC%
CMD

echo "[info] Input DCP : $IN_DCP"
echo "[info] Output dir: $OUT_DIR"
echo "[info] Tcl script: $TCL_SCRIPT"
echo "[info] Vivado bat: $VIVADO_BAT"
echo "[info] Stage dir : $STAGE_DIR"

if ! cmd.exe /c "$WIN_WRAPPER_CMD"; then
  echo "[error] Vivado failed; stage dir preserved at: $STAGE_DIR" >&2
  exit 1
fi

EXPECTED_BIT="$STAGE_OUT_DIR/ZCU104FPGATestHarness_spi_sd_ila.bit"
EXPECTED_LTX="$STAGE_OUT_DIR/spi_sd_ila.ltx"

if [[ ! -f "$EXPECTED_BIT" || ! -f "$EXPECTED_LTX" ]]; then
  echo "[error] Vivado completed without expected outputs; stage dir preserved at: $STAGE_DIR" >&2
  exit 1
fi

cp -af "$STAGE_OUT_DIR"/. "$OUT_DIR"/
echo "[info] Copied staged outputs back to: $OUT_DIR"