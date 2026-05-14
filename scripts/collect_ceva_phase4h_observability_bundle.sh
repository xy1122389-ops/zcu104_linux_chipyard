#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${1:-${ROOT_DIR}/reports/phase4h_observability_${TIMESTAMP}}"
DEFAULT_PROOF_LOG="${ROOT_DIR}/logs/phase4c6_20260513_230221/run.log"
PROOF_LOG="${PHASE4G_LOG_PATH:-${PHASE4C6_LOG_PATH:-$DEFAULT_PROOF_LOG}}"
MANIFEST="${ROOT_DIR}/linux-bringup/payload/ceva_runtime_launch_manifest.env"
DTS="${ROOT_DIR}/linux-bringup/dtb/chipyard-zcu104-fedora.dts"
SIDECAR_BIN="${ROOT_DIR}/sidecar/ceva_bt52_sidecar/build/sidecar.bin"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing Phase4-H bundle input: $path" >&2
    exit 1
  fi
}

record_hash() {
  local path="$1"
  local label="$2"

  if [[ -f "$path" ]]; then
    sha256sum "$path" | awk -v label="$label" '{print label "_SHA256=" $1}'
    stat -c "%s" "$path" | awk -v label="$label" '{print label "_SIZE=" $1}'
  else
    echo "${label}_SHA256=MISSING"
    echo "${label}_SIZE=MISSING"
  fi
}

require_file "$PROOF_LOG"
require_file "$MANIFEST"
require_file "$DTS"

mkdir -p "$OUT_DIR"

PHASE4G_LOG_PATH="$PROOF_LOG" \
PHASE4G_SKIP_BASELINE_CHECKS="${PHASE4G_SKIP_BASELINE_CHECKS:-0}" \
  bash "${ROOT_DIR}/scripts/check_ceva_phase4g_fedora_bluez_service_integration.sh" >"${OUT_DIR}/phase4g_check.txt"
PHASE4C6_LOG_PATH="$PROOF_LOG" bash "${ROOT_DIR}/scripts/check_ceva_phase4d_to_f_hardening_contract.sh" >"${OUT_DIR}/phase4d_to_f_check.txt"
PHASE4C6_LOG_PATH="$PROOF_LOG" bash "${ROOT_DIR}/scripts/check_ceva_phase4c_memory_ownership_contract.sh" >"${OUT_DIR}/phase4c_check.txt"

cp "$PROOF_LOG" "${OUT_DIR}/proof_run.log"
cp "$MANIFEST" "${OUT_DIR}/ceva_runtime_launch_manifest.env"
cp "$DTS" "${OUT_DIR}/chipyard-zcu104-fedora.dts"

{
  echo "CEVA Phase4-H observability bundle"
  echo "created=${TIMESTAMP}"
  echo "proof_log=${PROOF_LOG}"
  echo "bundle_dir=${OUT_DIR}"
  record_hash "$PROOF_LOG" "PROOF_LOG"
  record_hash "$MANIFEST" "MANIFEST"
  record_hash "$DTS" "DTS"
  record_hash "$SIDECAR_BIN" "SIDECAR_BIN"
  echo
  echo "Key proof markers:"
  grep -E 'CEVA BT5.2 registered as hci0|ceva_bt_open: OK|BT core running|PHASE25_USER_HCI_RESET_PASS|PHASE25_USER_HCI_RLV_PASS|PHASE25_USER_SMOKE_PASS|CEVA_PHASE25_SELFTEST_PASS|\[boot-owner\] claimed=yes' "$PROOF_LOG" || true
  echo
  echo "Failure marker scan:"
  grep -Ei 'Kernel panic|Oops|BUG:|Unable to handle|CEVA_PHASE25_.*_FAIL|PHASE25_USER_.*_FAIL' "$PROOF_LOG" | grep -Ev ': MISSING|FAIL/WARN|Searching for panic/error strings' || true
  echo
  echo "P4H_OBSERVABILITY_BUNDLE=PASS"
} >"${OUT_DIR}/SUMMARY.txt"

echo "PHASE4H_BUNDLE_DIR=${OUT_DIR}"
echo "P4H_OBSERVABILITY_BUNDLE=PASS"
