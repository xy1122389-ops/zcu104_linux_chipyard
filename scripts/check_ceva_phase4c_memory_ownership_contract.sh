#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="${ROOT_DIR}/scripts/ceva_reserved_memory_contract.sh"
ADDRESS_PLAN="${ROOT_DIR}/linux-bringup/ADDRESS_PLAN.md"
H4_DOC="${ROOT_DIR}/docs/bringup/ceva_bt52_phase3b_h4_sidecar_reserved_memory_packaging_20260512.md"
BOOT_OWNER_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4b3_boot_owner_readiness.sh"
DT_STUB_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4c3_dt_reserved_memory_stub.sh"
OPENSBI_CONSUMPTION_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4c4_opensbi_reserved_memory_consumption.sh"
OPENSBI_CARVEOUT_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4c5_opensbi_root_domain_carveout.sh"
OPENSBI_RUNTIME_PROOF_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4c5_runtime_root_domain_proof.sh"
LINUX_E2E_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4c6_linux_reserved_memory_end_to_end.sh"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing memory ownership input: $path" >&2
    exit 1
  fi
}

require_file "$CONTRACT"
require_file "$ADDRESS_PLAN"
require_file "$H4_DOC"
require_file "$BOOT_OWNER_CHECKER"
require_file "$DT_STUB_CHECKER"
require_file "$OPENSBI_CONSUMPTION_CHECKER"
require_file "$OPENSBI_CARVEOUT_CHECKER"
require_file "$OPENSBI_RUNTIME_PROOF_CHECKER"
require_file "$LINUX_E2E_CHECKER"

source "$CONTRACT"

bash "${ROOT_DIR}/scripts/check_ceva_sidecar_memory_contract.sh" >/dev/null
bash "$BOOT_OWNER_CHECKER" >/dev/null
bash "$DT_STUB_CHECKER" >/dev/null
bash "$OPENSBI_CONSUMPTION_CHECKER" >/dev/null
bash "$OPENSBI_CARVEOUT_CHECKER" >/dev/null
bash "$OPENSBI_RUNTIME_PROOF_CHECKER" >/dev/null
bash "$LINUX_E2E_CHECKER" >/dev/null

echo "CEVA reserved-memory ownership contract"
echo "current_mode=${CEVA_MEMORY_CURRENT_MODE}"
echo "target_mode=${CEVA_MEMORY_TARGET_MODE}"
echo "rollback_mode=${CEVA_MEMORY_ROLLBACK_MODE}"
echo "marker=${CEVA_SIDECAR_MARKER_START}..${CEVA_SIDECAR_MARKER_END}"
echo "image=${CEVA_SIDECAR_IMAGE_START}..${CEVA_SIDECAR_IMAGE_END}"
echo "vendor=${CEVA_VENDOR_IMAGE_START}..${CEVA_VENDOR_IMAGE_END}"
echo "proof=${CEVA_PROOF_IMAGE_START}..${CEVA_PROOF_IMAGE_END}"
echo "reserved=${CEVA_RUNTIME_RESERVED_START}..${CEVA_RUNTIME_RESERVED_END} size=${CEVA_RUNTIME_RESERVED_SIZE}"
echo "address_plan=${ADDRESS_PLAN}"
echo "h4_doc=${H4_DOC}"
echo "boot_owner_readiness=${BOOT_OWNER_CHECKER}"
echo "dt_reserved_memory_stub=${DT_STUB_CHECKER}"
echo "opensbi_reserved_memory_consumption=${OPENSBI_CONSUMPTION_CHECKER}"
echo "opensbi_root_domain_carveout=${OPENSBI_CARVEOUT_CHECKER}"
echo "opensbi_root_domain_runtime_proof=${OPENSBI_RUNTIME_PROOF_CHECKER}"
echo "linux_reserved_memory_e2e=${LINUX_E2E_CHECKER}"
echo "reservation_transfer_policy=${CEVA_RESERVED_MEMORY_TRANSFER_POLICY}"
echo "reservation_transfer_target=${CEVA_RESERVED_MEMORY_TRANSFER_TARGET}"
echo "reservation_dtb_node=${CEVA_RESERVED_MEMORY_DTB_NODE}"
echo "opensbi_carveout_policy=${CEVA_OPENSBI_CARVEOUT_POLICY}"
echo "opensbi_carveout_flags=${CEVA_OPENSBI_CARVEOUT_FLAGS}"
echo "opensbi_carveout_active=${CEVA_OPENSBI_CARVEOUT_ACTIVE}"
echo "P4C_MEMORY_OWNERSHIP_CONTRACT=PASS"
echo "P4C_BOOT_OWNER_MEMORY_ALIGNMENT=PASS"
echo "P4C_DT_RESERVED_MEMORY_STUB=PASS"
echo "P4C_OPENSBI_RESERVED_MEMORY_CONSUMPTION=PASS"
echo "P4C_OPENSBI_ROOT_DOMAIN_CARVEOUT=PASS"
echo "P4C_OPENSBI_ROOT_DOMAIN_RUNTIME_PROOF=PASS"
echo "P4C_LINUX_RESERVED_MEMORY_E2E=PASS"
echo "P4C_RESERVED_MEMORY_TRANSFER=PASS"