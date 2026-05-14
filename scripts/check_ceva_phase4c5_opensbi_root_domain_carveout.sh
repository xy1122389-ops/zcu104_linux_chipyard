#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MEMORY_CONTRACT="${ROOT_DIR}/scripts/ceva_reserved_memory_contract.sh"
C4_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4c4_opensbi_reserved_memory_consumption.sh"
OPENSBI_PLATFORM_C="/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/platform/generic/platform.c"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing OpenSBI root-domain carveout input: $path" >&2
    exit 1
  fi
}

require_text() {
  local needle="$1"
  local file="$2"

  if ! grep -Fq "$needle" "$file"; then
    echo "FAIL: missing '${needle}' in $file" >&2
    exit 1
  fi
}

source "$MEMORY_CONTRACT"

require_file "$MEMORY_CONTRACT"
require_file "$C4_CHECKER"
require_file "$OPENSBI_PLATFORM_C"

bash "$C4_CHECKER" >/dev/null

if [[ "$CEVA_OPENSBI_CARVEOUT_POLICY" != "LINUX_NO_MAP_OWNS_RESERVED_RANGE" ]]; then
  echo "FAIL: unexpected CEVA_OPENSBI_CARVEOUT_POLICY=$CEVA_OPENSBI_CARVEOUT_POLICY" >&2
  exit 1
fi

if [[ "$CEVA_OPENSBI_CARVEOUT_FLAGS" != "NONE_VALIDATE_AND_MARKER_ONLY" ]]; then
  echo "FAIL: unexpected CEVA_OPENSBI_CARVEOUT_FLAGS=$CEVA_OPENSBI_CARVEOUT_FLAGS" >&2
  exit 1
fi

if [[ "$CEVA_OPENSBI_CARVEOUT_ACTIVE" != "0" ]]; then
  echo "FAIL: unexpected CEVA_OPENSBI_CARVEOUT_ACTIVE=$CEVA_OPENSBI_CARVEOUT_ACTIVE" >&2
  exit 1
fi

require_text 'CEVA_OPENSBI_RESERVED_RUNTIME_FLAGS' "$OPENSBI_PLATFORM_C"
require_text 'ceva_reserved_memory_apply_root_carveout' "$OPENSBI_PLATFORM_C"
require_text '#define CEVA_OPENSBI_ENABLE_ROOT_CARVEOUT 0' "$OPENSBI_PLATFORM_C"
require_text 'because Linux reserved-memory owns this range' "$OPENSBI_PLATFORM_C"
require_text 'ceva_boot_owner_claim_marker(addr, size)' "$OPENSBI_PLATFORM_C"
require_text 'ret = ceva_reserved_memory_apply_root_carveout(fdt);' "$OPENSBI_PLATFORM_C"

echo "CEVA OpenSBI reserved-memory validation without root-domain carveout"
echo "platform_c=${OPENSBI_PLATFORM_C}"
echo "carveout_policy=${CEVA_OPENSBI_CARVEOUT_POLICY}"
echo "carveout_flags=${CEVA_OPENSBI_CARVEOUT_FLAGS}"
echo "carveout_active=${CEVA_OPENSBI_CARVEOUT_ACTIVE}"
echo "reserved_range=${CEVA_RUNTIME_RESERVED_START}..${CEVA_RUNTIME_RESERVED_END} size=${CEVA_RUNTIME_RESERVED_SIZE}"
echo "P4C_OPENSBI_ROOT_DOMAIN_CARVEOUT=PASS"
echo "P4C_OPENSBI_ROOT_DOMAIN_CARVEOUT_DISABLED=PASS"
echo "P4C_LINUX_NO_MAP_OWNS_RESERVED_MEMORY=PASS"
echo "P4C_OPENSBI_RUNTIME_VALIDATION=PASS"
echo "P4C_RUNTIME_RELEASE_FROM_OPENSBI=PASS"