#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MEMORY_CONTRACT="${ROOT_DIR}/scripts/ceva_reserved_memory_contract.sh"
PHASE4B3_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4b3_boot_owner_readiness.sh"
SIDECAR_MEMORY_CHECKER="${ROOT_DIR}/scripts/check_ceva_sidecar_memory_contract.sh"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing reservation transfer readiness input: $path" >&2
    exit 1
  fi
}

hex() {
  printf '%d' "$((16#${1#0x}))"
}

range_size() {
  local start="$1"
  local end="$2"
  printf '0x%X\n' "$((end - start + 1))"
}

source "$MEMORY_CONTRACT"

require_file "$MEMORY_CONTRACT"
require_file "$PHASE4B3_CHECKER"
require_file "$SIDECAR_MEMORY_CHECKER"

bash "$SIDECAR_MEMORY_CHECKER" >/dev/null
bash "$PHASE4B3_CHECKER" >/dev/null

if [[ "$CEVA_RESERVED_MEMORY_TRANSFER_POLICY" != "OPENSBI_BOOT_OWNER_ACTIVE" ]]; then
  echo "FAIL: unsupported transfer policy: ${CEVA_RESERVED_MEMORY_TRANSFER_POLICY}" >&2
  exit 1
fi

if [[ "$CEVA_RESERVED_MEMORY_TRANSFER_TARGET" != "DT_RESERVED_MEMORY_PLUS_OPENSBI_VALIDATE_MARKER" ]]; then
  echo "FAIL: unsupported transfer target: ${CEVA_RESERVED_MEMORY_TRANSFER_TARGET}" >&2
  exit 1
fi

if [[ "$CEVA_RESERVED_MEMORY_BOOT_OWNER_TARGET" != "OPENSBI" ]]; then
  echo "FAIL: unsupported boot owner target: ${CEVA_RESERVED_MEMORY_BOOT_OWNER_TARGET}" >&2
  exit 1
fi

if [[ "$CEVA_RESERVED_MEMORY_DTB_NODE" != "ceva_runtime_reserved" ]]; then
  echo "FAIL: unexpected DT reserved-memory node name: ${CEVA_RESERVED_MEMORY_DTB_NODE}" >&2
  exit 1
fi

if [[ "$CEVA_RESERVED_MEMORY_DTB_COMPAT" != "shared-dma-pool" ]]; then
  echo "FAIL: unexpected DT reserved-memory compat: ${CEVA_RESERVED_MEMORY_DTB_COMPAT}" >&2
  exit 1
fi

if [[ "$CEVA_RESERVED_MEMORY_REUSABLE" != "0" ]]; then
  echo "FAIL: reserved-memory window must not be reusable in this phase" >&2
  exit 1
fi

if [[ "$CEVA_RESERVED_MEMORY_NO_MAP" != "1" ]]; then
  echo "FAIL: reserved-memory window must stay no-map in this phase" >&2
  exit 1
fi

if [[ "$CEVA_RESERVED_MEMORY_TRANSFER_ACTIVE" != "1" ]]; then
  echo "FAIL: reservation transfer must be active in OpenSBI-owned phase" >&2
  exit 1
fi

if (( $(hex "$CEVA_SIDECAR_MARKER_START") >= $(hex "$CEVA_SIDECAR_IMAGE_START") )); then
  echo "FAIL: marker page must remain below sidecar image window for reservation transfer" >&2
  exit 1
fi

if (( $(hex "$CEVA_SIDECAR_IMAGE_END") + 1 != $(hex "$CEVA_VENDOR_IMAGE_START") )); then
  echo "FAIL: vendor window must remain contiguous after sidecar image window" >&2
  exit 1
fi

if (( $(hex "$CEVA_VENDOR_IMAGE_END") + 1 != $(hex "$CEVA_PROOF_IMAGE_START") )); then
  echo "FAIL: proof window must remain contiguous after vendor image window" >&2
  exit 1
fi

marker_size="$(range_size "$CEVA_SIDECAR_MARKER_START" "$CEVA_SIDECAR_MARKER_END")"
sidecar_size="$(range_size "$CEVA_SIDECAR_IMAGE_START" "$CEVA_SIDECAR_IMAGE_END")"
vendor_size="$(range_size "$CEVA_VENDOR_IMAGE_START" "$CEVA_VENDOR_IMAGE_END")"
proof_size="$(range_size "$CEVA_PROOF_IMAGE_START" "$CEVA_PROOF_IMAGE_END")"

echo "CEVA reserved-memory transfer readiness"
echo "transfer_policy=${CEVA_RESERVED_MEMORY_TRANSFER_POLICY}"
echo "transfer_target=${CEVA_RESERVED_MEMORY_TRANSFER_TARGET}"
echo "boot_owner_target=${CEVA_RESERVED_MEMORY_BOOT_OWNER_TARGET}"
echo "dtb_node=${CEVA_RESERVED_MEMORY_DTB_NODE}"
echo "dtb_compat=${CEVA_RESERVED_MEMORY_DTB_COMPAT}"
echo "reusable=${CEVA_RESERVED_MEMORY_REUSABLE}"
echo "no_map=${CEVA_RESERVED_MEMORY_NO_MAP}"
echo "transfer_active=${CEVA_RESERVED_MEMORY_TRANSFER_ACTIVE}"
echo "marker=${CEVA_SIDECAR_MARKER_START}..${CEVA_SIDECAR_MARKER_END} size=${marker_size}"
echo "sidecar=${CEVA_SIDECAR_IMAGE_START}..${CEVA_SIDECAR_IMAGE_END} size=${sidecar_size}"
echo "vendor=${CEVA_VENDOR_IMAGE_START}..${CEVA_VENDOR_IMAGE_END} size=${vendor_size}"
echo "proof=${CEVA_PROOF_IMAGE_START}..${CEVA_PROOF_IMAGE_END} size=${proof_size}"
echo "P4C_RESERVATION_TRANSFER_READINESS=PASS"
echo "P4C_RESERVED_MEMORY_DTB_STUB=PASS"
echo "P4C_OPENSBI_VALIDATE_MARKER_IMPLEMENTATION=PASS"