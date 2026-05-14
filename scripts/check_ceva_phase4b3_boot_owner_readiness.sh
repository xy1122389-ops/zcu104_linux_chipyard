#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="${ROOT_DIR}/scripts/ceva_runtime_launch_contract.sh"
PHASE4B_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4b_runtime_launch_contract.sh"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing boot-owner readiness input: $path" >&2
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

hex() {
  printf '%d' "$((16#${1#0x}))"
}

range_end() {
  local start="$1"
  local size="$2"
  printf '0x%X\n' "$((start + size - 1))"
}

source "$CONTRACT"

require_file "$CONTRACT"
require_file "$PHASE4B_CHECKER"
require_file "$CEVA_RUNTIME_MANIFEST_PATH"

require_text "CEVA_RUNTIME_BOOT_OWNER_METADATA_VERSION=${CEVA_RUNTIME_BOOT_OWNER_METADATA_VERSION}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_BOOT_OWNER_CLEAR_MARKER_POLICY=${CEVA_RUNTIME_BOOT_OWNER_CLEAR_MARKER_POLICY}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_BOOT_OWNER_STAGE_ORDER=${CEVA_RUNTIME_BOOT_OWNER_STAGE_ORDER}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_BOOT_OWNER_LINUX_HANDOFF_POLICY=${CEVA_RUNTIME_BOOT_OWNER_LINUX_HANDOFF_POLICY}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_BOOT_OWNER_SIDECAR_START_POLICY=${CEVA_RUNTIME_BOOT_OWNER_SIDECAR_START_POLICY}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_BOOT_OWNER_REQUIRED_READY_MARKER=${CEVA_RUNTIME_BOOT_OWNER_REQUIRED_READY_MARKER}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_CURRENT=${CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_CURRENT}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_ROLE=${CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_ROLE}" "$CEVA_RUNTIME_MANIFEST_PATH"
require_text "CEVA_RUNTIME_BOOT_OWNER_MARKER_ADDR=${CEVA_RUNTIME_BOOT_OWNER_MARKER_ADDR}" "$CEVA_RUNTIME_MANIFEST_PATH"

# shellcheck disable=SC1090
source "$CEVA_RUNTIME_MANIFEST_PATH"

if [[ "$CEVA_RUNTIME_LAUNCH_OWNER_CURRENT" != "OPENSBI" ]]; then
  echo "FAIL: boot-owner ownership must now be held by OPENSBI: ${CEVA_RUNTIME_LAUNCH_OWNER_CURRENT}" >&2
  exit 1
fi

if [[ "$CEVA_RUNTIME_LAUNCH_OWNER_TARGET" != "OPENSBI" ]]; then
  echo "FAIL: unexpected target owner for boot-owner readiness: ${CEVA_RUNTIME_LAUNCH_OWNER_TARGET}" >&2
  exit 1
fi

if [[ "$CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_CURRENT" != "GDB" ]]; then
  echo "FAIL: payload bootstrap fallback must remain GDB while runtime ownership is transferred" >&2
  exit 1
fi

if [[ "$CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_ROLE" != "DEBUG_FALLBACK_ONLY" ]]; then
  echo "FAIL: unexpected payload bootstrap role: ${CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_ROLE}" >&2
  exit 1
fi

if [[ "$CEVA_RUNTIME_STAGING_CONSUMER" != "OPENSBI_RESERVED_STAGING" ]]; then
  echo "FAIL: boot-owner ownership expects OPENSBI_RESERVED_STAGING consumer state" >&2
  exit 1
fi

if [[ "$CEVA_RUNTIME_STAGING_ACTIVE" != "1" ]]; then
  echo "FAIL: boot-owner ownership must be active with STAGING_ACTIVE=1" >&2
  exit 1
fi

if [[ "$CEVA_RUNTIME_BOOT_OWNER_METADATA_VERSION" != "1" ]]; then
  echo "FAIL: unsupported boot-owner metadata version: ${CEVA_RUNTIME_BOOT_OWNER_METADATA_VERSION}" >&2
  exit 1
fi

if [[ "$CEVA_RUNTIME_BOOT_OWNER_CLEAR_MARKER_POLICY" != "CLEAR_BEFORE_LOAD" ]]; then
  echo "FAIL: unsupported marker clear policy: ${CEVA_RUNTIME_BOOT_OWNER_CLEAR_MARKER_POLICY}" >&2
  exit 1
fi

if [[ "$CEVA_RUNTIME_BOOT_OWNER_STAGE_ORDER" != "MARKER,SIDECAR,VENDOR,PROOF" ]]; then
  echo "FAIL: unsupported stage order: ${CEVA_RUNTIME_BOOT_OWNER_STAGE_ORDER}" >&2
  exit 1
fi

if [[ "$CEVA_RUNTIME_BOOT_OWNER_LINUX_HANDOFF_POLICY" != "CONTINUE_WITHOUT_RUNTIME_START" ]]; then
  echo "FAIL: unsupported Linux handoff policy: ${CEVA_RUNTIME_BOOT_OWNER_LINUX_HANDOFF_POLICY}" >&2
  exit 1
fi

if [[ "$CEVA_RUNTIME_BOOT_OWNER_SIDECAR_START_POLICY" != "DEFERRED_UNTIL_OWNER_TRANSFER" ]]; then
  echo "FAIL: unsupported sidecar start policy: ${CEVA_RUNTIME_BOOT_OWNER_SIDECAR_START_POLICY}" >&2
  exit 1
fi

if [[ "$CEVA_RUNTIME_BOOT_OWNER_REQUIRED_READY_MARKER" != "SIDECAR_INGRESS_READY" ]]; then
  echo "FAIL: unsupported ready marker: ${CEVA_RUNTIME_BOOT_OWNER_REQUIRED_READY_MARKER}" >&2
  exit 1
fi

sidecar_end="$(range_end "$CEVA_RUNTIME_SIDECAR_IMAGE_LOAD_ADDR" "$CEVA_RUNTIME_SIDECAR_IMAGE_MAX_SIZE")"
marker_end="$(range_end "$CEVA_RUNTIME_SIDECAR_MARKER_PAGE_ADDR" "$CEVA_RUNTIME_SIDECAR_MARKER_PAGE_SIZE")"
vendor_end="$(range_end "$CEVA_RUNTIME_VENDOR_IMAGE_LOAD_ADDR" "$CEVA_RUNTIME_VENDOR_IMAGE_MAX_SIZE")"
proof_end="$(range_end "$CEVA_RUNTIME_PROOF_IMAGE_LOAD_ADDR" "$CEVA_RUNTIME_PROOF_IMAGE_MAX_SIZE")"

if (( $(hex "$CEVA_RUNTIME_SIDECAR_MARKER_PAGE_ADDR") >= $(hex "$CEVA_RUNTIME_SIDECAR_IMAGE_LOAD_ADDR") )); then
  echo "FAIL: boot-owner readiness expects the marker page to be staged before the sidecar image window" >&2
  exit 1
fi

echo "CEVA boot-owner readiness"
echo "manifest=${CEVA_RUNTIME_MANIFEST_PATH}"
echo "current_owner=${CEVA_RUNTIME_LAUNCH_OWNER_CURRENT}"
echo "target_owner=${CEVA_RUNTIME_LAUNCH_OWNER_TARGET}"
echo "payload_bootstrap_current=${CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_CURRENT}"
echo "payload_bootstrap_role=${CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_ROLE}"
echo "boot_owner_metadata_version=${CEVA_RUNTIME_BOOT_OWNER_METADATA_VERSION}"
echo "clear_marker_policy=${CEVA_RUNTIME_BOOT_OWNER_CLEAR_MARKER_POLICY}"
echo "stage_order=${CEVA_RUNTIME_BOOT_OWNER_STAGE_ORDER}"
echo "linux_handoff_policy=${CEVA_RUNTIME_BOOT_OWNER_LINUX_HANDOFF_POLICY}"
echo "sidecar_start_policy=${CEVA_RUNTIME_BOOT_OWNER_SIDECAR_START_POLICY}"
echo "required_ready_marker=${CEVA_RUNTIME_BOOT_OWNER_REQUIRED_READY_MARKER}"
echo "boot_owner_marker_addr=${CEVA_RUNTIME_BOOT_OWNER_MARKER_ADDR}"
echo "action_1=clear_marker_page:${CEVA_RUNTIME_SIDECAR_MARKER_PAGE_ADDR}..${marker_end}"
echo "action_2=observe_sidecar_window:${CEVA_RUNTIME_SIDECAR_IMAGE_LOAD_ADDR}..${sidecar_end}"
echo "action_3=observe_vendor_window:${CEVA_RUNTIME_VENDOR_IMAGE_LOAD_ADDR}..${vendor_end}"
echo "action_4=observe_proof_window:${CEVA_RUNTIME_PROOF_IMAGE_LOAD_ADDR}..${proof_end}"
echo "action_5=retain_gdb_only_as_payload_bootstrap_fallback"
echo "action_6=continue_linux_boot_without_runtime_start"
echo "P4B_BOOT_OWNER_METADATA_CONSUMPTION=PASS"
echo "P4B_BOOT_OWNER_ACTION_PLAN=PASS"
echo "P4B_BOOT_OWNER_RUNTIME_RELEASE=PASS"