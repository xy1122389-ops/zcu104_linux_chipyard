#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/run_ps_pl_release.tcl"
FPGA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_ZCU104_CFG="RocketZCU104LinuxBringupConfig"

resolve_latest_zcu104_cfg() {
  local prefix="${FPGA_DIR}/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness."
  local dir bit psu cfg latest_cfg="" latest_mtime=0 mtime=0

  shopt -s nullglob
  for dir in "${prefix}"*; do
    [[ -d "${dir}" ]] || continue
    case "${dir}" in
      *.bak.*|*.pre_sentinel_*) continue ;;
    esac

    bit="${dir}/obj/ZCU104FPGATestHarness.bit"
    psu="${dir}/obj/ip/zcu104ps/psu_init.tcl"
    [[ -f "${bit}" && -f "${psu}" ]] || continue

    cfg="${dir#${prefix}}"
    mtime=$(stat -c %Y "${bit}")
    if (( mtime > latest_mtime )); then
      latest_mtime="${mtime}"
      latest_cfg="${cfg}"
    fi
  done
  shopt -u nullglob

  [[ -n "${latest_cfg}" ]] || return 1
  printf '%s\n' "${latest_cfg}"
}

if [[ ! -f "$TCL_SCRIPT" ]]; then
  echo "Error: missing TCL script: $TCL_SCRIPT" >&2
  exit 1
fi

if [[ -z "${CHIPYARD_ZCU104_CFG:-}" ]]; then
  CHIPYARD_ZCU104_CFG="$DEFAULT_ZCU104_CFG"
  export CHIPYARD_ZCU104_CFG
elif [[ "${CHIPYARD_ZCU104_CFG}" == "latest" ]]; then
  if ! CHIPYARD_ZCU104_CFG="$(resolve_latest_zcu104_cfg)"; then
    echo "Error: could not locate any ZCU104 bitstream + psu_init.tcl pair under ${FPGA_DIR}/generated-src" >&2
    exit 1
  fi
  export CHIPYARD_ZCU104_CFG
fi

echo "[info] Using ZCU104 config: ${CHIPYARD_ZCU104_CFG}"

XSDB_BAT_DEFAULT='/mnt/e/PRO_APP/xilinx/Vivado/2021.2/bin/xsdb.bat'
XSDB_BAT="${XSDB_BAT:-$XSDB_BAT_DEFAULT}"

if [[ ! -f "$XSDB_BAT" ]]; then
  echo "Error: xsdb not found: $XSDB_BAT" >&2
  exit 2
fi

WIN_TCL=$(wslpath -w "$TCL_SCRIPT")
WIN_WRAPPER=$(mktemp /mnt/c/Windows/Temp/xsdb_releaseXXXX.cmd)
trap 'rm -f "$WIN_WRAPPER"' EXIT
WIN_WRAPPER_CMD=$(wslpath -w "$WIN_WRAPPER")
WIN_XSDB_BAT=$(wslpath -w "$XSDB_BAT")
WIN_CFG=${CHIPYARD_ZCU104_CFG}

cat > "$WIN_WRAPPER" <<CMD
@echo off
set "CHIPYARD_ZCU104_CFG=$WIN_CFG"
pushd C:\Windows\Temp
call "$WIN_XSDB_BAT" -eval "source {$WIN_TCL}"
set EC=%ERRORLEVEL%
popd
exit /b %EC%
CMD

exec cmd.exe /c "$WIN_WRAPPER_CMD"
