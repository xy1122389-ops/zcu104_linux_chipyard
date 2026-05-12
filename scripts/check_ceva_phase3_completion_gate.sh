#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="status"

if [[ "${1:-}" == "--require-pass" ]]; then
  MODE="require-pass"
elif [[ "${1:-}" == "--status" || -z "${1:-}" ]]; then
  MODE="status"
else
  echo "usage: $0 [--status|--require-pass]" >&2
  exit 2
fi

BLOCKERS=0

pass() {
  echo "PASS: $*"
}

block() {
  echo "BLOCKED: $*"
  BLOCKERS=$((BLOCKERS + 1))
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_file() {
  local file="$1"
  local label="$2"

  if [[ -s "${ROOT_DIR}/${file}" ]]; then
    pass "$label present (${file})"
  else
    block "$label missing (${file})"
  fi
}

require_text() {
  local file="$1"
  local text="$2"
  local label="$3"

  if [[ ! -s "${ROOT_DIR}/${file}" ]]; then
    block "$label missing source file (${file})"
    return
  fi

  if grep -Fq "$text" "${ROOT_DIR}/${file}"; then
    pass "$label"
  else
    block "$label not found in ${file}"
  fi
}

require_evidence_file() {
  local file="$1"
  local label="$2"

  if [[ -s "${ROOT_DIR}/docs/bringup/phase3_completion_evidence/${file}" ]]; then
    pass "$label evidence present (${file})"
    return 0
  else
    block "$label evidence missing (docs/bringup/phase3_completion_evidence/${file})"
    return 1
  fi
}

require_evidence_text() {
  local file="$1"
  local text="$2"
  local label="$3"

  if grep -Fq "$text" "${ROOT_DIR}/docs/bringup/phase3_completion_evidence/${file}"; then
    pass "$label"
  else
    block "$label missing token '$text' in ${file}"
  fi
}

echo "CEVA BT5.2 Phase3 completion gate"
echo "mode=${MODE}"

require_file \
  "docs/bringup/ceva_bt52_phase3b_h3_sidecar_marker_load_proof_20260512.md" \
  "H3 sidecar marker proof doc"
require_text \
  "docs/bringup/ceva_bt52_phase3b_h3_sidecar_marker_load_proof_20260512.md" \
  "H3_MARKER_PROOF=PASS" \
  "H3 marker proof PASS"

if bash "${ROOT_DIR}/scripts/check_ceva_sidecar_memory_contract.sh" >/tmp/phase3_completion_h4_memory.out 2>&1; then
  pass "H4 memory contract guard"
else
  cat /tmp/phase3_completion_h4_memory.out >&2 || true
  fail "H4 memory contract guard failed"
fi

if bash "${ROOT_DIR}/scripts/check_ceva_sidecar_no_synthetic_event.sh" >/tmp/phase3_completion_h9_no_synth.out 2>&1; then
  pass "H9 no-synthetic-event guard"
else
  cat /tmp/phase3_completion_h9_no_synth.out >&2 || true
  fail "H9 no-synthetic-event guard failed"
fi

require_file \
  "docs/bringup/ceva_bt52_phase3b_h7_vendor_runtime_asset_gate_20260512.md" \
  "H7 vendor asset gate doc"

if require_evidence_file "00_vendor_approval_closed.md" \
  "vendor source/blob approval closed"; then
  require_evidence_text "00_vendor_approval_closed.md" \
    "PHASE3_VENDOR_APPROVAL=PASS" \
    "vendor approval PASS token"
  require_evidence_text "00_vendor_approval_closed.md" \
    "APPROVED_SCOPE=local-build" \
    "vendor approval local-build scope token"
elif grep -Fq "Vendor source/link approval is not established" \
  "${ROOT_DIR}/docs/bringup/ceva_bt52_phase3b_h7_vendor_runtime_asset_gate_20260512.md"; then
  block "H7 approval remains recorded as blocked"
else
  block "vendor approval closure evidence is missing"
fi

require_file \
  "sidecar/ceva_bt52_sidecar/vendor_adapter_boundary.h" \
  "H8 local vendor adapter boundary"
require_file \
  "sidecar/ceva_bt52_sidecar/sidecar_event_bridge.c" \
  "H6 gated sidecar event bridge"

if require_evidence_file "01_vendor_runtime_link_pass.md" \
  "vendor runtime link"; then
  require_evidence_text "01_vendor_runtime_link_pass.md" \
    "PHASE3_VENDOR_RUNTIME_LINK=PASS" \
    "vendor runtime link PASS token"
  require_evidence_text "01_vendor_runtime_link_pass.md" \
    "NO_VENDOR_SOURCE_COMMITTED=PASS" \
    "vendor source not committed token"
fi

if require_evidence_file "02_rwip_init_and_driver_init_pass.md" \
  "rwip_init and rwip_driver_init marker chain"; then
  require_evidence_text "02_rwip_init_and_driver_init_pass.md" \
    "PHASE3_RWIP_INIT=PASS" \
    "rwip_init PASS token"
  require_evidence_text "02_rwip_init_and_driver_init_pass.md" \
    "PHASE3_RWIP_DRIVER_INIT=PASS" \
    "rwip_driver_init PASS token"
  require_evidence_text "02_rwip_init_and_driver_init_pass.md" \
    "SIDECAR_POST_RWIP_INIT" \
    "post-rwip-init marker token"
  require_evidence_text "02_rwip_init_and_driver_init_pass.md" \
    "SIDECAR_POST_RWIP_DRIVER_INIT" \
    "post-rwip-driver-init marker token"
fi

if require_evidence_file "03_real_ingress_consumed_pass.md" \
  "real HCI Reset ingress consumed by vendor runtime"; then
  require_evidence_text "03_real_ingress_consumed_pass.md" \
    "PHASE3_REAL_INGRESS_CONSUMED=PASS" \
    "real ingress consumed PASS token"
  require_evidence_text "03_real_ingress_consumed_pass.md" \
    "SYNTHETIC_DISABLED=PASS" \
    "synthetic-disabled token for ingress"
  require_evidence_text "03_real_ingress_consumed_pass.md" \
    "HCI_RESET_CMD=03 0C 00" \
    "Reset command byte token"
  require_evidence_text "03_real_ingress_consumed_pass.md" \
    "SIDECAR_CMD_CONSUMED" \
    "command consumed marker token"
fi

if require_evidence_file "04_real_reset_event_pass.md" \
  "real Reset Command Complete"; then
  require_evidence_text "04_real_reset_event_pass.md" \
    "PHASE3_REAL_RESET_EVENT=PASS" \
    "real Reset event PASS token"
  require_evidence_text "04_real_reset_event_pass.md" \
    "SYNTHETIC_DISABLED=PASS" \
    "synthetic-disabled token for Reset"
  require_evidence_text "04_real_reset_event_pass.md" \
    "RESET_CC_BYTES=0E 04 01 03 0C 00" \
    "Reset Command Complete byte token"
  require_evidence_text "04_real_reset_event_pass.md" \
    "LINUX_RX_REAL_EVENT" \
    "Linux real RX marker token for Reset"
fi

if require_evidence_file "05_real_rlv_event_pass.md" \
  "real Read Local Version Command Complete"; then
  require_evidence_text "05_real_rlv_event_pass.md" \
    "PHASE3_REAL_RLV_EVENT=PASS" \
    "real RLV event PASS token"
  require_evidence_text "05_real_rlv_event_pass.md" \
    "SYNTHETIC_DISABLED=PASS" \
    "synthetic-disabled token for RLV"
  require_evidence_text "05_real_rlv_event_pass.md" \
    "RLV_CC_PREFIX=0E 0C 01 01 10 00" \
    "RLV Command Complete prefix token"
  require_evidence_text "05_real_rlv_event_pass.md" \
    "LINUX_RX_REAL_EVENT" \
    "Linux real RX marker token for RLV"
fi

if require_evidence_file "06_synthetic_off_repeated_regression_pass.md" \
  "synthetic-off repeated Reset/RLV regression"; then
  require_evidence_text "06_synthetic_off_repeated_regression_pass.md" \
    "PHASE3_SYNTHETIC_OFF_REGRESSION=PASS" \
    "synthetic-off regression PASS token"
  require_evidence_text "06_synthetic_off_repeated_regression_pass.md" \
    "RESET_RLV_REPEAT_COUNT=" \
    "Reset/RLV repeat count token"
fi

if require_evidence_file "07_bluez_controlled_bringup_pass.md" \
  "controlled BlueZ bringup on real controller"; then
  require_evidence_text "07_bluez_controlled_bringup_pass.md" \
    "PHASE3_BLUEZ_CONTROLLED_BRINGUP=PASS" \
    "controlled BlueZ PASS token"
  require_evidence_text "07_bluez_controlled_bringup_pass.md" \
    "PHASE3_RESET_RLV_BASELINE_VERIFIED=PASS" \
    "Reset/RLV baseline verified before BlueZ token"
fi

if (( BLOCKERS == 0 )); then
  echo "PHASE3_COMPLETION_GATE=PASS"
  exit 0
fi

echo "PHASE3_COMPLETION_GATE=INCOMPLETE"
echo "PHASE3_COMPLETION_BLOCKERS=${BLOCKERS}"

if [[ "${MODE}" == "require-pass" ]]; then
  exit 1
fi

exit 0
