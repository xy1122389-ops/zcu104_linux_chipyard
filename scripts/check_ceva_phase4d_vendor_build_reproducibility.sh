#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="${ROOT_DIR}/scripts/ceva_reserved_memory_contract.sh"
LAUNCH_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4b_runtime_launch_contract.sh"
SIDECAR_MEMORY_CHECKER="${ROOT_DIR}/scripts/check_ceva_sidecar_memory_contract.sh"
SIDECAR_BUILD_SCRIPT="${ROOT_DIR}/scripts/build_ceva_sidecar.sh"
SIDECAR_DIR="${ROOT_DIR}/sidecar/ceva_bt52_sidecar"
SIDECAR_BUILD_DIR="${SIDECAR_DIR}/build"
MARKER_H="${SIDECAR_DIR}/marker.h"
LINKER_LD="${SIDECAR_DIR}/linker.ld"
MAKEFILE="${SIDECAR_DIR}/Makefile"
VENDOR_BOUNDARY_H="${SIDECAR_DIR}/vendor_adapter_boundary.h"
EVENT_BRIDGE_C="${SIDECAR_DIR}/sidecar_event_bridge.c"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing P4-D input: $path" >&2
    exit 1
  fi
}

require_text() {
  local needle="$1"
  local file="$2"

  if ! grep -Fq -- "$needle" "$file"; then
    echo "FAIL: missing '$needle' in $file" >&2
    exit 1
  fi
}

require_tool() {
  local tool_name="$1"

  if ! command -v "$tool_name" >/dev/null 2>&1; then
    echo "FAIL: required P4-D tool not found: $tool_name" >&2
    exit 1
  fi
}

hex_c_ull() {
  local value="${1#0x}"

  printf '0x%016XULL' "$((16#$value))"
}

hex_linker() {
  local value="${1#0x}"

  printf '0x%016X' "$((16#$value))"
}

require_file "$CONTRACT"
require_file "$LAUNCH_CHECKER"
require_file "$SIDECAR_MEMORY_CHECKER"
require_file "$SIDECAR_BUILD_SCRIPT"
require_file "$MARKER_H"
require_file "$LINKER_LD"
require_file "$MAKEFILE"
require_file "$VENDOR_BOUNDARY_H"
require_file "$EVENT_BRIDGE_C"

# shellcheck disable=SC1090
source "$CONTRACT"

export PATH="/root/chipyard/.oclaw-env/bin:/root/chipyard/.oclaw-env/riscv-tools/bin:${PATH}"

require_tool riscv64-unknown-elf-gcc
require_tool riscv64-unknown-elf-objcopy
require_tool riscv64-unknown-elf-objdump
require_tool riscv64-unknown-elf-nm
require_tool sha256sum
require_tool make

marker_c_value="$(hex_c_ull "$CEVA_SIDECAR_MARKER_START")"
image_c_value="$(hex_c_ull "$CEVA_SIDECAR_IMAGE_START")"
image_linker_value="$(hex_linker "$CEVA_SIDECAR_IMAGE_START")"

require_text "CEVA_BT52_SIDECAR_MARKER_BASE ${marker_c_value}" "$MARKER_H"
require_text "CEVA_BT52_SIDECAR_IMAGE_BASE ${image_c_value}" "$MARKER_H"
require_text "ORIGIN = ${image_linker_value}" "$LINKER_LD"
require_text "LENGTH = 64K" "$LINKER_LD"
require_text "-ffreestanding" "$MAKEFILE"
require_text "-fno-builtin" "$MAKEFILE"
require_text "-nostdlib" "$MAKEFILE"
require_text "-nostartfiles" "$MAKEFILE"
require_text "-mcmodel=medany" "$MAKEFILE"
require_text "-Wl,--gc-sections" "$MAKEFILE"
require_text '-Wl,-Map=$(TARGET).map' "$MAKEFILE"
require_text "CEVA_BT52_VENDOR_ADAPTER_ABI_VERSION" "$VENDOR_BOUNDARY_H"
require_text "struct ceva_bt52_vendor_runtime_ops" "$VENDOR_BOUNDARY_H"
require_text "ceva_bt52_sidecar_publish_vendor_event" "$EVENT_BRIDGE_C"

bash "$LAUNCH_CHECKER" >/dev/null
bash "$SIDECAR_MEMORY_CHECKER" >/dev/null

restricted_assets="$(find "$SIDECAR_DIR" \
  -path "$SIDECAR_BUILD_DIR" -prune -o \
  -type f \( -name '*.a' -o -name '*.so' -o -name '*.o' -o -name '*.elf' -o -name '*.bin' -o -name '*.hex' -o -name '*.dat' -o -name '*.blob' \) \
  -print)"

if [[ -n "$restricted_assets" ]]; then
  echo "FAIL: restricted/generated assets are present under sidecar source:" >&2
  echo "$restricted_assets" >&2
  exit 1
fi

bash "$SIDECAR_BUILD_SCRIPT" >/dev/null
first_hash="$(sha256sum "${SIDECAR_BUILD_DIR}/sidecar.bin" | awk '{print $1}')"
undefined_symbols="$(riscv64-unknown-elf-nm -u "${SIDECAR_BUILD_DIR}/sidecar.elf" || true)"

if [[ -n "$undefined_symbols" ]]; then
  echo "FAIL: sidecar image has undefined symbols" >&2
  echo "$undefined_symbols" >&2
  exit 1
fi

bash "$SIDECAR_BUILD_SCRIPT" >/dev/null
second_hash="$(sha256sum "${SIDECAR_BUILD_DIR}/sidecar.bin" | awk '{print $1}')"

if [[ "$first_hash" != "$second_hash" ]]; then
  echo "FAIL: sidecar binary hash changed across clean rebuilds" >&2
  echo "first=${first_hash}" >&2
  echo "second=${second_hash}" >&2
  exit 1
fi

sidecar_size="$(stat -c %s "${SIDECAR_BUILD_DIR}/sidecar.bin")"

echo "CEVA Phase4-D vendor build reproducibility"
echo "marker=${CEVA_SIDECAR_MARKER_START}..${CEVA_SIDECAR_MARKER_END}"
echo "image=${CEVA_SIDECAR_IMAGE_START}..${CEVA_SIDECAR_IMAGE_END}"
echo "vendor=${CEVA_VENDOR_IMAGE_START}..${CEVA_VENDOR_IMAGE_END}"
echo "proof=${CEVA_PROOF_IMAGE_START}..${CEVA_PROOF_IMAGE_END}"
echo "sidecar_bin_sha256=${first_hash}"
echo "sidecar_bin_size=${sidecar_size}"
echo "P4D_VENDOR_BUILD_REPRODUCIBILITY=PASS"
echo "P4D_SIDECAR_BUILD_DETERMINISTIC=PASS"
echo "P4D_RESTRICTED_ASSETS_NOT_COMMITTED=PASS"
echo "P4D_VENDOR_ADAPTER_BOUNDARY=PASS"
echo "P4D_RUNTIME_STAGING_CONTRACT=PASS"