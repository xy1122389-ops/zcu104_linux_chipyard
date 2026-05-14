#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MEMORY_CONTRACT="${ROOT_DIR}/scripts/ceva_reserved_memory_contract.sh"
RESERVATION_READINESS_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4c2_reservation_transfer_readiness.sh"
DTS_PATH="${ROOT_DIR}/linux-bringup/dtb/chipyard-zcu104-fedora.dts"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing DT reserved-memory stub input: $path" >&2
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

NODE_ADDR_HEX="$(printf '%x' "$((CEVA_RUNTIME_RESERVED_START))")"

require_file "$MEMORY_CONTRACT"
require_file "$RESERVATION_READINESS_CHECKER"
require_file "$DTS_PATH"

bash "$RESERVATION_READINESS_CHECKER" >/dev/null

require_text 'reserved-memory {' "$DTS_PATH"
require_text '#address-cells = <1>;' "$DTS_PATH"
require_text '#size-cells = <1>;' "$DTS_PATH"
require_text 'ranges;' "$DTS_PATH"
require_text "${CEVA_RESERVED_MEMORY_DTB_NODE}@${NODE_ADDR_HEX} {" "$DTS_PATH"
require_text "compatible = \"${CEVA_RESERVED_MEMORY_DTB_COMPAT}\";" "$DTS_PATH"
require_text "reg = <${CEVA_RUNTIME_RESERVED_START,,} ${CEVA_RUNTIME_RESERVED_SIZE,,}>;" "$DTS_PATH"

if [[ "$CEVA_RESERVED_MEMORY_NO_MAP" == "1" ]]; then
  require_text 'no-map;' "$DTS_PATH"
fi

if [[ "$CEVA_RESERVED_MEMORY_REUSABLE" != "0" ]]; then
  echo "FAIL: reusable reserved-memory is not supported in this phase" >&2
  exit 1
fi

if [[ "$CEVA_RESERVED_MEMORY_TRANSFER_ACTIVE" != "1" ]]; then
  echo "FAIL: DT stub phase must reflect active OpenSBI-owned reservation transfer" >&2
  exit 1
fi

echo "CEVA DT reserved-memory stub"
echo "dts=${DTS_PATH}"
echo "node=${CEVA_RESERVED_MEMORY_DTB_NODE}@${NODE_ADDR_HEX}"
echo "reg=${CEVA_RUNTIME_RESERVED_START}..${CEVA_RUNTIME_RESERVED_END} size=${CEVA_RUNTIME_RESERVED_SIZE}"
echo "compat=${CEVA_RESERVED_MEMORY_DTB_COMPAT}"
echo "no_map=${CEVA_RESERVED_MEMORY_NO_MAP}"
echo "reusable=${CEVA_RESERVED_MEMORY_REUSABLE}"
echo "transfer_active=${CEVA_RESERVED_MEMORY_TRANSFER_ACTIVE}"
echo "P4C_DT_RESERVED_MEMORY_STUB=PASS"
echo "P4C_OPENSBI_VALIDATE_MARKER_IMPLEMENTATION=PASS"