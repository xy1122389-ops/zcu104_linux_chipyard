#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FPGA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

SUB_PROJECT="vcu118"
CONFIG=""
FLASHED_PROGRAM=""
LOG_DIR="${FPGA_DIR}/logs"
SKIP_BITSTREAM=0
VIVADO_SETTINGS="${VIVADO_SETTINGS:-}"
VIVADO_BAT=""

usage() {
  cat <<'USAGE'
Usage:
  build_bit_mcs.sh [options]

Options:
  --sub-project <name>      FPGA sub project (default: vcu118)
  --config <name>           Override config class (default: board default)
  --flashed-program <path>  Optional raw binary loaded by write_cfgmem.tcl
  --vivado-settings <path>  Path to settings64.sh
  --vivado-bat <path>       Path to vivado.bat (for WSL + Windows Vivado)
  --log-dir <path>          Log output directory (default: fpga/logs)
  --skip-bitstream          Skip make bitstream and only generate mcs from existing bit
  -h, --help                Show this help

Examples:
  ./scripts/build_bit_mcs.sh --sub-project vcu118
  ./scripts/build_bit_mcs.sh --sub-project zcu104 --config RocketZCU104NoDDRConfig
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sub-project)
      SUB_PROJECT="$2"
      shift 2
      ;;
    --config)
      CONFIG="$2"
      shift 2
      ;;
    --flashed-program)
      FLASHED_PROGRAM="$2"
      shift 2
      ;;
    --vivado-settings)
      VIVADO_SETTINGS="$2"
      shift 2
      ;;
    --vivado-bat)
      VIVADO_BAT="$2"
      shift 2
      ;;
    --log-dir)
      LOG_DIR="$2"
      shift 2
      ;;
    --skip-bitstream)
      SKIP_BITSTREAM=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option $1" >&2
      usage
      exit 1
      ;;
  esac
done

case "${SUB_PROJECT}" in
  vcu118)
    BOARD="vcu118"
    MODEL="VCU118FPGATestHarness"
    MODEL_PACKAGE="chipyard.fpga.vcu118"
    DEFAULT_CONFIG="RocketVCU118Config"
    CFGMEM_IFACE="spix8"
    CFGMEM_SIZE="256"
    ;;
  zcu104)
    BOARD="zcu104"
    MODEL="ZCU104FPGATestHarness"
    MODEL_PACKAGE="chipyard.fpga.zcu104"
    DEFAULT_CONFIG="RocketZCU104Config"
    # The generated zcu104 bitstream sets SPI_BUSWIDTH=1.
    CFGMEM_IFACE="spix1"
    CFGMEM_SIZE="64"
    ;;
  zcu102)
    BOARD="zcu102"
    MODEL="ZCU102FPGATestHarness"
    MODEL_PACKAGE="chipyard.fpga.zcu102"
    DEFAULT_CONFIG="RocketZCU102Config"
    CFGMEM_IFACE="spix1"
    CFGMEM_SIZE="64"
    ;;
  vc707)
    BOARD="vc707"
    MODEL="VC707FPGATestHarness"
    MODEL_PACKAGE="chipyard.fpga.vc707"
    DEFAULT_CONFIG="RocketVC707Config"
    CFGMEM_IFACE="bpix16"
    CFGMEM_SIZE="128"
    ;;
  nexysvideo)
    BOARD="nexys_video"
    MODEL="NexysVideoHarness"
    MODEL_PACKAGE="chipyard.fpga.nexysvideo"
    DEFAULT_CONFIG="RocketNexysVideoConfig"
    CFGMEM_IFACE="spix4"
    CFGMEM_SIZE="32"
    ;;
  arty35t)
    BOARD="arty"
    MODEL="Arty35THarness"
    MODEL_PACKAGE="chipyard.fpga.arty"
    DEFAULT_CONFIG="TinyRocketArtyConfig"
    CFGMEM_IFACE="spix4"
    CFGMEM_SIZE="16"
    ;;
  arty100t)
    BOARD="arty_a7_100"
    MODEL="Arty100THarness"
    MODEL_PACKAGE="chipyard.fpga.arty100t"
    DEFAULT_CONFIG="RocketArty100TConfig"
    CFGMEM_IFACE="spix4"
    CFGMEM_SIZE="16"
    ;;
  *)
    echo "Error: unsupported sub project: ${SUB_PROJECT}" >&2
    exit 1
    ;;
esac

if [[ -z "${CONFIG}" ]]; then
  CONFIG="${DEFAULT_CONFIG}"
fi

LONG_NAME="${MODEL_PACKAGE}.${MODEL}.${CONFIG}"
BUILD_DIR="${FPGA_DIR}/generated-src/${LONG_NAME}"
BIT_FILE="${BUILD_DIR}/obj/${MODEL}.bit"
MCS_FILE="${BUILD_DIR}/obj/system.mcs"
WRITE_CFGMEM_TCL="${FPGA_DIR}/scripts/write_cfgmem_generic.tcl"

to_vivado_path() {
  local p="$1"
  if [[ -n "${VIVADO_BAT}" ]]; then
    wslpath -m "$p"
  else
    echo "$p"
  fi
}

run_vivado() {
  if [[ -n "${VIVADO_BAT}" ]]; then
    cmd.exe /c "${VIVADO_BAT}" "$@"
  else
    vivado "$@"
  fi
}

mkdir -p "${LOG_DIR}"
TS="$(date +%Y%m%d_%H%M%S)"
BIT_LOG="${LOG_DIR}/${SUB_PROJECT}_${CONFIG}_bitstream_${TS}.log"
MCS_LOG="${LOG_DIR}/${SUB_PROJECT}_${CONFIG}_mcs_${TS}.log"

cd "${FPGA_DIR}"

if [[ ${SKIP_BITSTREAM} -eq 0 ]]; then
  echo "[info] building bitstream: SUB_PROJECT=${SUB_PROJECT}, CONFIG=${CONFIG}"
  set -o pipefail
  make "SUB_PROJECT=${SUB_PROJECT}" "CONFIG=${CONFIG}" bitstream 2>&1 | tee "${BIT_LOG}"
  set +o pipefail
  echo "[info] bitstream log: ${BIT_LOG}"
fi

if [[ ! -f "${BIT_FILE}" ]]; then
  echo "Error: bit file not found: ${BIT_FILE}" >&2
  exit 1
fi

if [[ -z "${VIVADO_BAT}" ]] && ! command -v vivado >/dev/null 2>&1; then
  if [[ -n "${VIVADO_SETTINGS}" ]]; then
    if [[ ! -f "${VIVADO_SETTINGS}" ]]; then
      echo "Error: --vivado-settings path not found: ${VIVADO_SETTINGS}" >&2
      exit 1
    fi
    # shellcheck disable=SC1090
    source "${VIVADO_SETTINGS}" >/dev/null 2>&1 || true
  fi
fi

if [[ -z "${VIVADO_BAT}" ]] && ! command -v vivado >/dev/null 2>&1; then
  for p in /tools/Xilinx/Vivado/*/settings64.sh /opt/Xilinx/Vivado/*/settings64.sh; do
    if [[ -f "${p}" ]]; then
      # shellcheck disable=SC1090
      source "${p}" >/dev/null 2>&1 || true
      break
    fi
  done
fi

if [[ -z "${VIVADO_BAT}" ]] && ! command -v vivado >/dev/null 2>&1; then
  if [[ -n "${VIVADO_SETTINGS}" ]]; then
    maybe_bat="${VIVADO_SETTINGS%/settings64.sh}/bin/vivado.bat"
    if [[ -f "${maybe_bat}" ]] && command -v cmd.exe >/dev/null 2>&1; then
      VIVADO_BAT="$(wslpath -w "${maybe_bat}")"
    fi
  fi
fi

if [[ -z "${VIVADO_BAT}" ]] && ! command -v vivado >/dev/null 2>&1; then
  for p in /mnt/*/PRO_APP/xilinx/Vivado/*/bin/vivado.bat; do
    if [[ -f "${p}" ]] && command -v cmd.exe >/dev/null 2>&1; then
      VIVADO_BAT="$(wslpath -w "${p}")"
      break
    fi
  done
fi

if [[ -z "${VIVADO_BAT}" ]] && ! command -v vivado >/dev/null 2>&1; then
  echo "Error: no usable Vivado found. Provide --vivado-settings or --vivado-bat." >&2
  exit 1
fi

if [[ -n "${VIVADO_BAT}" ]]; then
  if [[ ! -f "$(wslpath -u "${VIVADO_BAT}")" ]]; then
    echo "Error: --vivado-bat path not found: ${VIVADO_BAT}" >&2
    exit 1
  fi
fi

if [[ ! -f "${WRITE_CFGMEM_TCL}" ]]; then
  echo "Error: write_cfgmem.tcl not found: ${WRITE_CFGMEM_TCL}" >&2
  exit 1
fi

echo "[info] generating mcs: ${MCS_FILE}"
set -o pipefail
if [[ -n "${FLASHED_PROGRAM}" ]]; then
  run_vivado -nojournal -mode batch -source "$(to_vivado_path "${WRITE_CFGMEM_TCL}")" \
    -tclargs "${CFGMEM_IFACE}" "${CFGMEM_SIZE}" "$(to_vivado_path "${MCS_FILE}")" "$(to_vivado_path "${BIT_FILE}")" "$(to_vivado_path "${FLASHED_PROGRAM}")" 2>&1 | tee "${MCS_LOG}"
else
  run_vivado -nojournal -mode batch -source "$(to_vivado_path "${WRITE_CFGMEM_TCL}")" \
    -tclargs "${CFGMEM_IFACE}" "${CFGMEM_SIZE}" "$(to_vivado_path "${MCS_FILE}")" "$(to_vivado_path "${BIT_FILE}")" 2>&1 | tee "${MCS_LOG}"
fi
set +o pipefail

echo "[done] bit: ${BIT_FILE}"
if [[ -f "${MCS_FILE}" ]]; then
  echo "[done] mcs: ${MCS_FILE}"
elif [[ -f "${MCS_FILE%.mcs}_primary.mcs" ]] && [[ -f "${MCS_FILE%.mcs}_secondary.mcs" ]]; then
  echo "[done] mcs primary: ${MCS_FILE%.mcs}_primary.mcs"
  echo "[done] mcs secondary: ${MCS_FILE%.mcs}_secondary.mcs"
else
  echo "[warn] expected mcs output not found at ${MCS_FILE}"
fi
echo "[done] mcs log: ${MCS_LOG}"
