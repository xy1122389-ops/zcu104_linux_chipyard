#!/usr/bin/env bash
set -euo pipefail

# stable_init.sh — Unified ZCU104 LinuxBringup init
# Burns correct 19MB LinuxBringup bit, runs psu_init, leaves GPIO[31]=0

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/xsdb_stable_init.tcl"
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

resolve_generated_pair() {
    local candidate_psu
    local candidate_bit

    if [[ -n "${CHIPYARD_BITSTREAM_LINUX:-}" && -n "${CHIPYARD_PSU_INIT_TCL_LINUX:-}" ]]; then
        [[ -f "${CHIPYARD_BITSTREAM_LINUX}" && -f "${CHIPYARD_PSU_INIT_TCL_LINUX}" ]] && return 0
        echo "Error: direct CHIPYARD_BITSTREAM_LINUX / CHIPYARD_PSU_INIT_TCL_LINUX pair is invalid" >&2
        exit 1
    fi

    for candidate_psu in \
        "$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/obj/ip/zcu104ps/psu_init.tcl" \
        "$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Phase0bConfig/obj/ip/zcu104ps/psu_init.tcl"
    do
        candidate_bit="$(dirname "$(dirname "$(dirname "$candidate_psu")")")/ZCU104FPGATestHarness.bit"
        if [[ -f "$candidate_psu" && -f "$candidate_bit" ]]; then
            CHIPYARD_PSU_INIT_TCL_LINUX="$candidate_psu"
            CHIPYARD_BITSTREAM_LINUX="$candidate_bit"
            CHIPYARD_PSU_INIT_TCL_WINDOWS=$(wslpath -w "$candidate_psu")
            CHIPYARD_BITSTREAM_WINDOWS=$(wslpath -w "$candidate_bit")
            export CHIPYARD_PSU_INIT_TCL_LINUX CHIPYARD_BITSTREAM_LINUX
            export CHIPYARD_PSU_INIT_TCL_WINDOWS CHIPYARD_BITSTREAM_WINDOWS
            return 0
        fi
    done

    while IFS= read -r candidate_psu; do
        candidate_bit="$(dirname "$(dirname "$(dirname "$candidate_psu")")")/ZCU104FPGATestHarness.bit"
        if [[ -f "$candidate_bit" ]]; then
            CHIPYARD_PSU_INIT_TCL_LINUX="$candidate_psu"
            CHIPYARD_BITSTREAM_LINUX="$candidate_bit"
            CHIPYARD_PSU_INIT_TCL_WINDOWS=$(wslpath -w "$candidate_psu")
            CHIPYARD_BITSTREAM_WINDOWS=$(wslpath -w "$candidate_bit")
            export CHIPYARD_PSU_INIT_TCL_LINUX CHIPYARD_BITSTREAM_LINUX
            export CHIPYARD_PSU_INIT_TCL_WINDOWS CHIPYARD_BITSTREAM_WINDOWS
            return 0
        fi
    done < <(find "$FPGA_DIR/generated-src" -type f -path '*/obj/ip/zcu104ps/psu_init.tcl' 2>/dev/null | sort)

    echo "Error: could not locate a usable ZCU104 bitstream + psu_init.tcl pair under $FPGA_DIR/generated-src" >&2
    exit 1
}

if [[ ! -f "$TCL_SCRIPT" ]]; then
    echo "Error: missing $TCL_SCRIPT" >&2
    exit 1
fi

resolve_generated_pair

WIN_TCL=$(wslpath -w "$TCL_SCRIPT")
XSDB_BAT="${XSDB_BAT:-/mnt/e/PRO_APP/xilinx/Vivado/2021.2/bin/xsdb.bat}"
WIN_XSDB_BAT=$(wslpath -w "$XSDB_BAT")

WIN_WRAPPER=$(mktemp /mnt/c/Windows/Temp/xsdb_stable_initXXXX.cmd)
OUT_LOG=$(mktemp /tmp/stable_init_outXXXX.log)
trap 'rm -f "$WIN_WRAPPER"' EXIT
WIN_WRAPPER_CMD=$(wslpath -w "$WIN_WRAPPER")

cat > "$WIN_WRAPPER" <<CMD
@echo off
pushd C:\\Windows\\Temp
set "CHIPYARD_BITSTREAM_LINUX=${CHIPYARD_BITSTREAM_LINUX}"
set "CHIPYARD_PSU_INIT_TCL_LINUX=${CHIPYARD_PSU_INIT_TCL_LINUX}"
set "CHIPYARD_BITSTREAM_WINDOWS=${CHIPYARD_BITSTREAM_WINDOWS}"
set "CHIPYARD_PSU_INIT_TCL_WINDOWS=${CHIPYARD_PSU_INIT_TCL_WINDOWS}"
call "$WIN_XSDB_BAT" -eval "source {$WIN_TCL}"
set EC=%ERRORLEVEL%
popd
exit /b %EC%
CMD

echo "[stable_init] Programming LinuxBringup bit + full PS init + GPIO[31]=0"
echo "[stable_init] TCL: $WIN_TCL"
echo "[stable_init] bitstream: ${CHIPYARD_BITSTREAM_LINUX}"
echo "[stable_init] psu_init: ${CHIPYARD_PSU_INIT_TCL_LINUX}"
echo ""
cmd.exe /c "$WIN_WRAPPER_CMD" 2>&1 | tee "$OUT_LOG"
EC=$?
echo ""
if grep -Eiq 'ERROR in source psu_init\.tcl|couldn.t read file .*psu_init\.tcl|missing psu_init\.tcl|PSU target not available|ERROR in ' "$OUT_LOG"; then
    echo "[stable_init] FAILED (detected xsdb error output)" >&2
    exit 1
fi

if ! grep -Fq '=== STABLE INIT COMPLETE ===' "$OUT_LOG"; then
    echo "[stable_init] FAILED (missing completion marker)" >&2
    exit 1
fi

if [[ $EC -eq 0 ]]; then
    echo "[stable_init] SUCCESS — ready for J-Link"
else
    echo "[stable_init] FAILED (exit code $EC)" >&2
fi
exit $EC
