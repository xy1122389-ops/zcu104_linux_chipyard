#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MEMORY_CONTRACT="${ROOT_DIR}/scripts/ceva_reserved_memory_contract.sh"
DT_STUB_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4c3_dt_reserved_memory_stub.sh"
REBUILD_PAYLOAD="${ROOT_DIR}/rebuild_payload.sh"
OPENSBI_PLATFORM_C="/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/platform/generic/platform.c"
OPENSBI_OBJECTS_MK="/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/platform/generic/objects.mk"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing OpenSBI reserved-memory consumption input: $path" >&2
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
require_file "$DT_STUB_CHECKER"
require_file "$REBUILD_PAYLOAD"
require_file "$OPENSBI_PLATFORM_C"
require_file "$OPENSBI_OBJECTS_MK"

bash "$DT_STUB_CHECKER" >/dev/null

require_text 'ceva_reserved_memory_validate' "$OPENSBI_PLATFORM_C"
require_text 'fdt_path_offset(fdt, "/reserved-memory")' "$OPENSBI_PLATFORM_C"
require_text 'fdt_get_node_addr_size(fdt, node_offset, 0, &addr, &size)' "$OPENSBI_PLATFORM_C"
require_text 'sbi_printf("ceva: reserved-memory stub consumed' "$OPENSBI_PLATFORM_C"
require_text 'CEVA_OPENSBI_RESERVED_NODE_NAME' "$OPENSBI_OBJECTS_MK"
require_text 'CEVA_OPENSBI_RESERVED_COMPAT' "$OPENSBI_OBJECTS_MK"
require_text 'CEVA_OPENSBI_RESERVED_START' "$OPENSBI_OBJECTS_MK"
require_text 'CEVA_OPENSBI_RESERVED_SIZE' "$OPENSBI_OBJECTS_MK"
require_text 'CEVA_OPENSBI_RESERVED_NO_MAP' "$OPENSBI_OBJECTS_MK"
require_text 'CEVA_OPENSBI_RESERVED_NODE_NAME="$CEVA_OPENSBI_RESERVED_NODE_NAME"' "$REBUILD_PAYLOAD"
require_text 'CEVA_OPENSBI_RESERVED_COMPAT="$CEVA_OPENSBI_RESERVED_COMPAT"' "$REBUILD_PAYLOAD"
require_text 'CEVA_OPENSBI_RESERVED_START="$CEVA_OPENSBI_RESERVED_START"' "$REBUILD_PAYLOAD"
require_text 'CEVA_OPENSBI_RESERVED_SIZE="$CEVA_OPENSBI_RESERVED_SIZE"' "$REBUILD_PAYLOAD"
require_text 'CEVA_OPENSBI_RESERVED_NO_MAP="$CEVA_OPENSBI_RESERVED_NO_MAP"' "$REBUILD_PAYLOAD"
require_text 'print_manifest_field "CEVA_OPENSBI_RESERVED_NODE_NAME"' "$REBUILD_PAYLOAD"
require_text 'print_manifest_field "CEVA_OPENSBI_RESERVED_START"' "$REBUILD_PAYLOAD"

echo "CEVA OpenSBI reserved-memory consumption"
echo "platform_c=${OPENSBI_PLATFORM_C}"
echo "objects_mk=${OPENSBI_OBJECTS_MK}"
printf 'reserved_node=%s@%x\n' "$CEVA_RESERVED_MEMORY_DTB_NODE" "$((CEVA_RUNTIME_RESERVED_START))"
echo "reserved_range=${CEVA_RUNTIME_RESERVED_START}..${CEVA_RUNTIME_RESERVED_END} size=${CEVA_RUNTIME_RESERVED_SIZE}"
echo "reserved_compat=${CEVA_RESERVED_MEMORY_DTB_COMPAT}"
echo "reserved_no_map=${CEVA_RESERVED_MEMORY_NO_MAP}"
echo "P4C_OPENSBI_RESERVED_MEMORY_CONSUMPTION=PASS"
echo "P4C_OPENSBI_VALIDATE_MARKER_IMPLEMENTATION=PASS"
echo "P4C_RUNTIME_RELEASE_FROM_OPENSBI=PASS"