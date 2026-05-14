#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="${ROOT_DIR}/scripts/ceva_runtime_launch_contract.sh"
MEMORY_CONTRACT="${ROOT_DIR}/scripts/ceva_reserved_memory_contract.sh"
REBUILD_PAYLOAD="${ROOT_DIR}/rebuild_payload.sh"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing launch contract input: $path" >&2
    exit 1
  fi
}

require_exec() {
  local path="$1"

  require_file "$path"
  if [[ ! -x "$path" ]]; then
    echo "FAIL: launch contract input is not executable: $path" >&2
    exit 1
  fi
}

require_text() {
  local needle="$1"
  local file="$2"

  if ! grep -Fq "$needle" "$file"; then
    echo "FAIL: missing '$needle' in $file" >&2
    exit 1
  fi
}

hex() {
  printf '%d' "$((16#${1#0x}))"
}

range_end() {
  local start="$1"
  local size="$2"
  printf '0x%X\n' "$((start + size - 1))"
}

value_in_range() {
  local value start end
  value=$(hex "$1")
  start=$(hex "$2")
  end=$(hex "$3")
  (( value >= start && value <= end ))
}

overlaps() {
  local start_a end_a start_b end_b
  start_a=$(hex "$1")
  end_a=$(hex "$2")
  start_b=$(hex "$3")
  end_b=$(hex "$4")
  (( start_a <= end_b && start_b <= end_a ))
}

check_hex_var() {
  local name="$1"
  local value="${!name:-}"

  if [[ ! "$value" =~ ^0x[0-9A-Fa-f]+$ ]]; then
    echo "FAIL: invalid hex format for ${name}: ${value}" >&2
    exit 1
  fi
}

check_non_overlap() {
  local name_a="$1" start_a="$2" end_a="$3" name_b="$4" start_b="$5" end_b="$6"

  if overlaps "$start_a" "$end_a" "$start_b" "$end_b"; then
    echo "FAIL: ${name_a} ${start_a}..${end_a} overlaps ${name_b} ${start_b}..${end_b}" >&2
    exit 1
  fi
}

source "$CONTRACT"
source "$MEMORY_CONTRACT"

require_file "$CONTRACT"
require_file "$MEMORY_CONTRACT"
require_file "$REBUILD_PAYLOAD"
require_file "$CEVA_RUNTIME_BITSTREAM"
require_file "$CEVA_RUNTIME_PAYLOAD_BIN"
require_file "$CEVA_RUNTIME_DTB"
require_file "$CEVA_RUNTIME_SDBOOT_BIN"
require_file "$CEVA_RUNTIME_MANIFEST_PATH"
require_exec "$CEVA_RUNTIME_PROGRAM_BIT_SCRIPT"
require_exec "$CEVA_RUNTIME_JLINK_GUARD_SCRIPT"
require_file "$CEVA_RUNTIME_PHASE2_LAUNCH_GDB"
require_file "$CEVA_RUNTIME_PHASE2_CAPTURE_GDB"
require_exec "$CEVA_RUNTIME_MANIFEST_GENERATOR"
require_file "$CEVA_RUNTIME_RECOVERY_RUNBOOK"
require_file "$CEVA_RUNTIME_RECOVERY_REPORT"
require_exec "$CEVA_RUNTIME_GDB_BIN"

require_text "CEVA_RUNTIME_PRODUCTION_OWNER=${CEVA_RUNTIME_PRODUCTION_OWNER}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_MANIFEST_PURPOSE=${CEVA_RUNTIME_MANIFEST_PURPOSE}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_PAYLOAD_LOAD_ADDR=${CEVA_RUNTIME_PAYLOAD_LOAD_ADDR}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_DTB_LOAD_ADDR=${CEVA_RUNTIME_DTB_LOAD_ADDR}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_LINUX_ENTRY_PA=${CEVA_RUNTIME_LINUX_ENTRY_PA}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_OPENSBI_PAYLOAD_OFFSET=${CEVA_RUNTIME_OPENSBI_PAYLOAD_OFFSET}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_LAUNCH_OWNER_CURRENT=${CEVA_RUNTIME_LAUNCH_OWNER_CURRENT}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_LAUNCH_OWNER_TARGET=${CEVA_RUNTIME_LAUNCH_OWNER_TARGET}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_CURRENT=${CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_CURRENT}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_ROLE=${CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_ROLE}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_STAGING_OWNER=${CEVA_RUNTIME_STAGING_OWNER}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_STAGING_CONSUMER=${CEVA_RUNTIME_STAGING_CONSUMER}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_STAGING_ACTIVE=${CEVA_RUNTIME_STAGING_ACTIVE}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_SIDECAR_IMAGE_LOAD_ADDR=${CEVA_RUNTIME_SIDECAR_IMAGE_LOAD_ADDR}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_SIDECAR_IMAGE_MAX_SIZE=${CEVA_RUNTIME_SIDECAR_IMAGE_MAX_SIZE}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_SIDECAR_ENTRY_ADDR=${CEVA_RUNTIME_SIDECAR_ENTRY_ADDR}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_SIDECAR_MARKER_PAGE_ADDR=${CEVA_RUNTIME_SIDECAR_MARKER_PAGE_ADDR}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_SIDECAR_MARKER_PAGE_SIZE=${CEVA_RUNTIME_SIDECAR_MARKER_PAGE_SIZE}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_SIDECAR_MARKER_WINDOW_MODE=${CEVA_RUNTIME_SIDECAR_MARKER_WINDOW_MODE}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_BOOT_OWNER_MARKER_ADDR=${CEVA_RUNTIME_BOOT_OWNER_MARKER_ADDR}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_VENDOR_IMAGE_LOAD_ADDR=${CEVA_RUNTIME_VENDOR_IMAGE_LOAD_ADDR}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_VENDOR_IMAGE_MAX_SIZE=${CEVA_RUNTIME_VENDOR_IMAGE_MAX_SIZE}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_PROOF_IMAGE_LOAD_ADDR=${CEVA_RUNTIME_PROOF_IMAGE_LOAD_ADDR}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_PROOF_IMAGE_MAX_SIZE=${CEVA_RUNTIME_PROOF_IMAGE_MAX_SIZE}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_SIDECAR_MARKER_START=${CEVA_SIDECAR_MARKER_START}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_SIDECAR_IMAGE_START=${CEVA_SIDECAR_IMAGE_START}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text 'source "$PAYLOAD_MANIFEST_PATH"' "$REBUILD_PAYLOAD"
require_text 'CEVA_RUNTIME_MANIFEST_CHECK_ONLY' "$REBUILD_PAYLOAD"
require_text 'P4B_MANIFEST_FIELD ' "$REBUILD_PAYLOAD"
require_text 'FW_PAYLOAD_FDT_ADDR="${CEVA_RUNTIME_DTB_LOAD_ADDR}"' "$REBUILD_PAYLOAD"
require_text 'FW_PAYLOAD_FDT_ADDR="$FW_PAYLOAD_FDT_ADDR"' "$REBUILD_PAYLOAD"
require_text 'FW_PAYLOAD_OFFSET="${CEVA_RUNTIME_OPENSBI_PAYLOAD_OFFSET}"' "$REBUILD_PAYLOAD"
require_text 'FW_PAYLOAD_OFFSET="$FW_PAYLOAD_OFFSET"' "$REBUILD_PAYLOAD"

# shellcheck disable=SC1090
source "$CEVA_RUNTIME_MANIFEST_PATH"

if (( CEVA_RUNTIME_OPENSBI_PAYLOAD_OFFSET != (CEVA_RUNTIME_LINUX_ENTRY_PA - CEVA_RUNTIME_PAYLOAD_LOAD_ADDR) )); then
  echo "FAIL: manifest payload offset does not match linux entry staging" >&2
  exit 1
fi

for name in \
  CEVA_RUNTIME_PAYLOAD_LOAD_ADDR \
  CEVA_RUNTIME_DTB_LOAD_ADDR \
  CEVA_RUNTIME_LINUX_ENTRY_PA \
  CEVA_RUNTIME_OPENSBI_LOAD_START \
  CEVA_RUNTIME_OPENSBI_LOAD_END \
  CEVA_RUNTIME_OPENSBI_PAYLOAD_OFFSET \
  CEVA_RUNTIME_SIDECAR_IMAGE_LOAD_ADDR \
  CEVA_RUNTIME_SIDECAR_IMAGE_MAX_SIZE \
  CEVA_RUNTIME_SIDECAR_ENTRY_ADDR \
  CEVA_RUNTIME_SIDECAR_MARKER_PAGE_ADDR \
  CEVA_RUNTIME_SIDECAR_MARKER_PAGE_SIZE \
  CEVA_RUNTIME_VENDOR_IMAGE_LOAD_ADDR \
  CEVA_RUNTIME_VENDOR_IMAGE_MAX_SIZE \
  CEVA_RUNTIME_PROOF_IMAGE_LOAD_ADDR \
  CEVA_RUNTIME_PROOF_IMAGE_MAX_SIZE; do
  check_hex_var "$name"
done

if [[ "$CEVA_RUNTIME_LAUNCH_OWNER_CURRENT" != "OPENSBI" ]]; then
  echo "FAIL: current launch owner changed unexpectedly: ${CEVA_RUNTIME_LAUNCH_OWNER_CURRENT}" >&2
  exit 1
fi

if [[ "$CEVA_RUNTIME_LAUNCH_OWNER_TARGET" != "OPENSBI" ]]; then
  echo "FAIL: target launch owner must be OPENSBI: ${CEVA_RUNTIME_LAUNCH_OWNER_TARGET}" >&2
  exit 1
fi

if [[ "$CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_CURRENT" != "GDB" ]]; then
  echo "FAIL: payload bootstrap fallback changed unexpectedly: ${CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_CURRENT}" >&2
  exit 1
fi

if [[ "$CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_ROLE" != "DEBUG_FALLBACK_ONLY" ]]; then
  echo "FAIL: payload bootstrap role changed unexpectedly: ${CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_ROLE}" >&2
  exit 1
fi

if [[ "$CEVA_RUNTIME_STAGING_OWNER" != "OPENSBI" ]]; then
  echo "FAIL: staging owner changed unexpectedly: ${CEVA_RUNTIME_STAGING_OWNER}" >&2
  exit 1
fi

if [[ "$CEVA_RUNTIME_STAGING_ACTIVE" != "1" ]]; then
  echo "FAIL: staging active must be 1 for boot-owner-owned phase: ${CEVA_RUNTIME_STAGING_ACTIVE}" >&2
  exit 1
fi

if [[ "$CEVA_RUNTIME_STAGING_CONSUMER" != "OPENSBI_RESERVED_STAGING" ]]; then
  echo "FAIL: staging consumer must be OPENSBI_RESERVED_STAGING: ${CEVA_RUNTIME_STAGING_CONSUMER}" >&2
  exit 1
fi

sidecar_end="$(range_end "$CEVA_RUNTIME_SIDECAR_IMAGE_LOAD_ADDR" "$CEVA_RUNTIME_SIDECAR_IMAGE_MAX_SIZE")"
marker_end="$(range_end "$CEVA_RUNTIME_SIDECAR_MARKER_PAGE_ADDR" "$CEVA_RUNTIME_SIDECAR_MARKER_PAGE_SIZE")"
vendor_end="$(range_end "$CEVA_RUNTIME_VENDOR_IMAGE_LOAD_ADDR" "$CEVA_RUNTIME_VENDOR_IMAGE_MAX_SIZE")"
proof_end="$(range_end "$CEVA_RUNTIME_PROOF_IMAGE_LOAD_ADDR" "$CEVA_RUNTIME_PROOF_IMAGE_MAX_SIZE")"

if ! value_in_range "$CEVA_RUNTIME_SIDECAR_ENTRY_ADDR" "$CEVA_RUNTIME_SIDECAR_IMAGE_LOAD_ADDR" "$sidecar_end"; then
  echo "FAIL: sidecar entry ${CEVA_RUNTIME_SIDECAR_ENTRY_ADDR} is outside sidecar window ${CEVA_RUNTIME_SIDECAR_IMAGE_LOAD_ADDR}..${sidecar_end}" >&2
  exit 1
fi

if ! value_in_range "$CEVA_RUNTIME_SIDECAR_MARKER_PAGE_ADDR" "$CEVA_RUNTIME_SIDECAR_IMAGE_LOAD_ADDR" "$sidecar_end"; then
  if [[ "$CEVA_RUNTIME_SIDECAR_MARKER_WINDOW_MODE" != "INDEPENDENT" ]]; then
    echo "FAIL: marker page is outside sidecar window but marker mode is not INDEPENDENT" >&2
    exit 1
  fi
  check_non_overlap SidecarMarker "$CEVA_RUNTIME_SIDECAR_MARKER_PAGE_ADDR" "$marker_end" SidecarImage "$CEVA_RUNTIME_SIDECAR_IMAGE_LOAD_ADDR" "$sidecar_end"
fi

check_non_overlap SidecarImage "$CEVA_RUNTIME_SIDECAR_IMAGE_LOAD_ADDR" "$sidecar_end" VendorImage "$CEVA_RUNTIME_VENDOR_IMAGE_LOAD_ADDR" "$vendor_end"
check_non_overlap SidecarImage "$CEVA_RUNTIME_SIDECAR_IMAGE_LOAD_ADDR" "$sidecar_end" ProofImage "$CEVA_RUNTIME_PROOF_IMAGE_LOAD_ADDR" "$proof_end"
check_non_overlap VendorImage "$CEVA_RUNTIME_VENDOR_IMAGE_LOAD_ADDR" "$vendor_end" ProofImage "$CEVA_RUNTIME_PROOF_IMAGE_LOAD_ADDR" "$proof_end"
check_non_overlap SidecarMarker "$CEVA_RUNTIME_SIDECAR_MARKER_PAGE_ADDR" "$marker_end" VendorImage "$CEVA_RUNTIME_VENDOR_IMAGE_LOAD_ADDR" "$vendor_end"
check_non_overlap SidecarMarker "$CEVA_RUNTIME_SIDECAR_MARKER_PAGE_ADDR" "$marker_end" ProofImage "$CEVA_RUNTIME_PROOF_IMAGE_LOAD_ADDR" "$proof_end"

if value_in_range "$CEVA_RUNTIME_DTB_LOAD_ADDR" "$CEVA_RUNTIME_SIDECAR_IMAGE_LOAD_ADDR" "$sidecar_end" || \
   value_in_range "$CEVA_RUNTIME_DTB_LOAD_ADDR" "$CEVA_RUNTIME_SIDECAR_MARKER_PAGE_ADDR" "$marker_end" || \
   value_in_range "$CEVA_RUNTIME_DTB_LOAD_ADDR" "$CEVA_RUNTIME_VENDOR_IMAGE_LOAD_ADDR" "$vendor_end" || \
   value_in_range "$CEVA_RUNTIME_DTB_LOAD_ADDR" "$CEVA_RUNTIME_PROOF_IMAGE_LOAD_ADDR" "$proof_end"; then
  echo "FAIL: DTB load address ${CEVA_RUNTIME_DTB_LOAD_ADDR} overlaps a staging window" >&2
  exit 1
fi

for region in "${CEVA_MEMORY_REGIONS[@]}"; do
  IFS=: read -r name start end <<<"$region"
  check_non_overlap SidecarMarker "$CEVA_RUNTIME_SIDECAR_MARKER_PAGE_ADDR" "$marker_end" "$name" "$start" "$end"
  check_non_overlap SidecarImage "$CEVA_RUNTIME_SIDECAR_IMAGE_LOAD_ADDR" "$sidecar_end" "$name" "$start" "$end"
  check_non_overlap VendorImage "$CEVA_RUNTIME_VENDOR_IMAGE_LOAD_ADDR" "$vendor_end" "$name" "$start" "$end"
  check_non_overlap ProofImage "$CEVA_RUNTIME_PROOF_IMAGE_LOAD_ADDR" "$proof_end" "$name" "$start" "$end"
done

echo "CEVA runtime launch contract"
echo "mode=${CEVA_RUNTIME_LAUNCH_MODE}"
echo "production_owner=${CEVA_RUNTIME_PRODUCTION_OWNER}"
echo "manifest_purpose=${CEVA_RUNTIME_MANIFEST_PURPOSE}"
echo "manifest=${CEVA_RUNTIME_MANIFEST_PATH}"
echo "opensbi_input=FW_PAYLOAD_FDT_ADDR<-CEVA_RUNTIME_DTB_LOAD_ADDR"
echo "opensbi_layout=FW_PAYLOAD_OFFSET<-CEVA_RUNTIME_OPENSBI_PAYLOAD_OFFSET"
echo "launch_owner_current=${CEVA_RUNTIME_LAUNCH_OWNER_CURRENT}"
echo "launch_owner_target=${CEVA_RUNTIME_LAUNCH_OWNER_TARGET}"
echo "payload_bootstrap_current=${CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_CURRENT}"
echo "payload_bootstrap_role=${CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_ROLE}"
echo "staging_owner=${CEVA_RUNTIME_STAGING_OWNER}"
echo "staging_consumer=${CEVA_RUNTIME_STAGING_CONSUMER}"
echo "staging_active=${CEVA_RUNTIME_STAGING_ACTIVE}"
echo "boot_owner_marker_addr=${CEVA_RUNTIME_BOOT_OWNER_MARKER_ADDR}"
echo "sidecar_window=${CEVA_RUNTIME_SIDECAR_IMAGE_LOAD_ADDR}..${sidecar_end}"
echo "sidecar_entry=${CEVA_RUNTIME_SIDECAR_ENTRY_ADDR}"
echo "marker_window=${CEVA_RUNTIME_SIDECAR_MARKER_PAGE_ADDR}..${marker_end}"
echo "marker_mode=${CEVA_RUNTIME_SIDECAR_MARKER_WINDOW_MODE}"
echo "vendor_window=${CEVA_RUNTIME_VENDOR_IMAGE_LOAD_ADDR}..${vendor_end}"
echo "proof_window=${CEVA_RUNTIME_PROOF_IMAGE_LOAD_ADDR}..${proof_end}"
echo "bitstream=${CEVA_RUNTIME_BITSTREAM}"
echo "payload=${CEVA_RUNTIME_PAYLOAD_BIN}"
echo "dtb=${CEVA_RUNTIME_DTB}"
echo "launch_gdb=${CEVA_RUNTIME_PHASE2_LAUNCH_GDB}"
echo "capture_gdb=${CEVA_RUNTIME_PHASE2_CAPTURE_GDB}"
echo "program_bit=${CEVA_RUNTIME_PROGRAM_BIT_SCRIPT}"
echo "jlink_guard=${CEVA_RUNTIME_JLINK_GUARD_SCRIPT}"
echo "manifest_generator=${CEVA_RUNTIME_MANIFEST_GENERATOR}"
echo "recovery_runbook=${CEVA_RUNTIME_RECOVERY_RUNBOOK}"
echo "recovery_report=${CEVA_RUNTIME_RECOVERY_REPORT}"
echo "P4B_OPENSBI_MANIFEST_INPUT=PASS"
echo "P4B_RUNTIME_LAUNCH_CONTRACT=PASS"
echo "P4B_SIDECAR_VENDOR_STAGING_METADATA=PASS"
echo "P4B_LAUNCH_OWNER_TRANSFER=PASS"
echo "P4B_OPENSBI_RUNTIME_START=PASS"