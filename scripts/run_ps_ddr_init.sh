#!/usr/bin/env bash
set -euo pipefail

# Preferred: add xsct to PATH, or export XSCT=/path/to/xsct
# Fallback on this machine: Windows xsdb.bat from Vivado 2021.2

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/run_ps_ddr_init.tcl"
FPGA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_ZCU104_CFG="RocketZCU104LinuxBringupConfig"

usage() {
  cat <<'EOF'
Usage:
  run_ps_ddr_init.sh [--cfg CONFIG]
  run_ps_ddr_init.sh --latest
  run_ps_ddr_init.sh --bit /path/to/ZCU104FPGATestHarness.bit [--psu-init /path/to/psu_init.tcl]
  run_ps_ddr_init.sh /path/to/ZCU104FPGATestHarness.bit

Examples:
  CHIPYARD_ZCU104_CFG=RocketZCU104LinuxBringupConfig bash scripts/run_ps_ddr_init.sh
  bash scripts/run_ps_ddr_init.sh --latest
  bash scripts/run_ps_ddr_init.sh --bit generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/obj/ZCU104FPGATestHarness.bit

Notes:
  - When --bit is used, the script infers psu_init.tcl from obj/ip/zcu104ps/psu_init.tcl unless --psu-init is given.
  - When no arguments are given, it uses CHIPYARD_ZCU104_CFG or the default config.
EOF
}

canonicalize_path() {
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1"
  else
    readlink -f "$1"
  fi
}

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

unset CHIPYARD_BITSTREAM_LINUX CHIPYARD_BITSTREAM_WINDOWS
unset CHIPYARD_PSU_INIT_TCL_LINUX CHIPYARD_PSU_INIT_TCL_WINDOWS

DIRECT_BIT=""
DIRECT_PSU_INIT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cfg)
      [[ $# -ge 2 ]] || { echo "Error: --cfg requires an argument" >&2; exit 1; }
      CHIPYARD_ZCU104_CFG="$2"
      export CHIPYARD_ZCU104_CFG
      shift 2
      ;;
    --latest)
      CHIPYARD_ZCU104_CFG="latest"
      export CHIPYARD_ZCU104_CFG
      shift
      ;;
    --bit)
      [[ $# -ge 2 ]] || { echo "Error: --bit requires an argument" >&2; exit 1; }
      DIRECT_BIT="$2"
      shift 2
      ;;
    --psu-init)
      [[ $# -ge 2 ]] || { echo "Error: --psu-init requires an argument" >&2; exit 1; }
      DIRECT_PSU_INIT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$DIRECT_BIT" ]]; then
        DIRECT_BIT="$1"
        shift
      else
        echo "Error: unexpected extra argument: $1" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

if [[ $# -gt 0 ]]; then
  echo "Error: unexpected extra arguments: $*" >&2
  usage >&2
  exit 1
fi

if [[ -n "$DIRECT_BIT" ]]; then
  DIRECT_BIT=$(canonicalize_path "$DIRECT_BIT")
  if [[ ! -f "$DIRECT_BIT" ]]; then
    echo "Error: bitstream not found: $DIRECT_BIT" >&2
    exit 1
  fi

  if [[ -z "$DIRECT_PSU_INIT" ]]; then
    DIRECT_PSU_INIT="$(dirname "$DIRECT_BIT")/ip/zcu104ps/psu_init.tcl"
  fi
  DIRECT_PSU_INIT=$(canonicalize_path "$DIRECT_PSU_INIT")
  if [[ ! -f "$DIRECT_PSU_INIT" ]]; then
    echo "Error: psu_init.tcl not found: $DIRECT_PSU_INIT" >&2
    exit 1
  fi

  CHIPYARD_BITSTREAM_LINUX="$DIRECT_BIT"
  CHIPYARD_BITSTREAM_WINDOWS=$(wslpath -w "$DIRECT_BIT")
  CHIPYARD_PSU_INIT_TCL_LINUX="$DIRECT_PSU_INIT"
  CHIPYARD_PSU_INIT_TCL_WINDOWS=$(wslpath -w "$DIRECT_PSU_INIT")
  export CHIPYARD_BITSTREAM_LINUX CHIPYARD_BITSTREAM_WINDOWS
  export CHIPYARD_PSU_INIT_TCL_LINUX CHIPYARD_PSU_INIT_TCL_WINDOWS
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

if [[ -n "${CHIPYARD_BITSTREAM_LINUX:-}" ]]; then
  echo "[info] Using direct bitstream: ${CHIPYARD_BITSTREAM_LINUX}"
  echo "[info] Using direct psu_init: ${CHIPYARD_PSU_INIT_TCL_LINUX}"
else
  echo "[info] Using ZCU104 config: ${CHIPYARD_ZCU104_CFG}"
fi

if [[ -n "${XSCT:-}" ]]; then
  exec "$XSCT" "$TCL_SCRIPT"
fi

if command -v xsct >/dev/null 2>&1; then
  exec xsct "$TCL_SCRIPT"
fi

if command -v xsdb >/dev/null 2>&1; then
  exec xsdb "$TCL_SCRIPT"
fi

XSDB_BAT_DEFAULT='/mnt/e/PRO_APP/xilinx/Vivado/2021.2/bin/xsdb.bat'
XSDB_BAT="${XSDB_BAT:-$XSDB_BAT_DEFAULT}"

if [[ ! -f "$XSDB_BAT" ]]; then
  echo "Error: xsct/xsdb not found in PATH, and XSDB_BAT does not exist: $XSDB_BAT" >&2
  echo "Set XSCT=/path/to/xsct or XSDB_BAT=/path/to/xsdb.bat and retry." >&2
  exit 2
fi

if [[ ! -d /mnt/c/Windows/Temp ]]; then
  echo "Error: /mnt/c/Windows/Temp not found; cannot create Windows-side xsdb wrapper." >&2
  exit 3
fi

WIN_TCL=$(wslpath -w "$TCL_SCRIPT")
WIN_WRAPPER=$(mktemp /mnt/c/Windows/Temp/xsdb_wrapperXXXX.cmd)
trap 'rm -f "$WIN_WRAPPER"' EXIT
WIN_WRAPPER_CMD=$(wslpath -w "$WIN_WRAPPER")
WIN_XSDB_BAT=$(wslpath -w "$XSDB_BAT")
WIN_CFG=${CHIPYARD_ZCU104_CFG}
WIN_DIRECT_PATH_LINES=""

if [[ -n "${CHIPYARD_BITSTREAM_LINUX:-}" ]]; then
  WIN_DIRECT_PATH_LINES+="set \"CHIPYARD_BITSTREAM_LINUX=${CHIPYARD_BITSTREAM_LINUX}\""$'\n'
  WIN_DIRECT_PATH_LINES+="set \"CHIPYARD_BITSTREAM_WINDOWS=${CHIPYARD_BITSTREAM_WINDOWS}\""$'\n'
  WIN_DIRECT_PATH_LINES+="set \"CHIPYARD_PSU_INIT_TCL_LINUX=${CHIPYARD_PSU_INIT_TCL_LINUX}\""$'\n'
  WIN_DIRECT_PATH_LINES+="set \"CHIPYARD_PSU_INIT_TCL_WINDOWS=${CHIPYARD_PSU_INIT_TCL_WINDOWS}\""$'\n'
fi

cat > "$WIN_WRAPPER" <<CMD
@echo off
set "CHIPYARD_ZCU104_CFG=$WIN_CFG"
set "SKIP_FPGA_PROGRAM=${SKIP_FPGA_PROGRAM:-0}"
${WIN_DIRECT_PATH_LINES}pushd C:\Windows\Temp
call "$WIN_XSDB_BAT" -eval "source {$WIN_TCL}"
set EC=%ERRORLEVEL%
popd
exit /b %EC%
CMD

exec cmd.exe /c "$WIN_WRAPPER_CMD"
