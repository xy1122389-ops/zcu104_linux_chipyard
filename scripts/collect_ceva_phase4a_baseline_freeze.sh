#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG="${P4A_CFG:-RocketZCU104Phase0bConfig}"
OUT="${1:-/tmp/ceva_phase4a_baseline_freeze.txt}"

BITSTREAM="generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.${CFG}/obj/ZCU104FPGATestHarness.bit"
PAYLOAD_FILES=(
  "linux-bringup/payload/fw_payload.bin"
  "linux-bringup/payload/ceva_runtime_launch_manifest.env"
  "linux-bringup/dtb/chipyard-zcu104-fedora.dtb"
)
OPTIONAL_PAYLOAD_FILES=(
  "src/main/resources/zcu104/sdboot/build/sdboot.bin"
)
RECOVERY_FILES=(
  "scripts/program_phase0b_bit.sh"
  "scripts/start_jlink_server.sh"
  "scripts/jlink_guard.sh"
  "run_phase2_ceva_bt_linux.sh"
  "docs/bringup/ceva_bt52_phase25_runbook_20260512.md"
  "docs/bringup/phase3b_recovery_reports/phase3b_h3_recovery_20260513_001254.md"
)
PHASE4_ENTRY_CHECKERS=(
  "scripts/check_ceva_phase4b_runtime_launch_contract.sh"
  "scripts/check_ceva_phase4c_memory_ownership_contract.sh"
)

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "ERROR: required freeze input missing: $path" >&2
    exit 1
  fi
}

print_file_record() {
  local path="$1"
  local hash size

  hash="$(sha256sum "$path" | awk '{print $1}')"
  size="$(stat -c %s "$path")"
  printf '%s  %12s  %s\n' "$hash" "$size" "$path"

}

print_optional_file_record() {
  local path="$1"

  if [[ -f "$path" ]]; then
    print_file_record "$path"
  else
    printf 'MISSING  %12s  %s\n' '-' "$path"
  fi
}

cd "$ROOT_DIR"

require_file "$BITSTREAM"
for path in "${PAYLOAD_FILES[@]}"; do
  require_file "$path"
done
for path in "${RECOVERY_FILES[@]}"; do
  require_file "$path"
done
for path in "${PHASE4_ENTRY_CHECKERS[@]}"; do
  require_file "$path"
done

mapfile -t EVIDENCE_FILES < <(find docs/bringup/phase3_completion_evidence -maxdepth 1 -type f -name '*.md' | sort)
if [[ ${#EVIDENCE_FILES[@]} -eq 0 ]]; then
  echo "ERROR: no Phase3 evidence files found under docs/bringup/phase3_completion_evidence" >&2
  exit 1
fi

{
  echo "CEVA BT5.2 Phase4-A release baseline freeze"
  echo "timestamp=$(date -Iseconds)"
  echo "cfg=$CFG"
  echo
  echo "========== HEAD =========="
  echo "commit=$(git rev-parse HEAD)"
  echo "branch=$(git branch --show-current)"
  git log -1 --oneline --decorate
  echo
  echo "========== GIT STATUS =========="
  git status --short
  echo
  echo "========== PHASE3 GATE =========="
  bash scripts/check_ceva_phase3_completion_gate.sh --require-pass
  echo
  echo "========== PHASE4 ENTRY CONTRACTS =========="
  bash scripts/check_ceva_phase4b_runtime_launch_contract.sh
  echo
  bash scripts/check_ceva_phase4c_memory_ownership_contract.sh
  echo
  echo "========== FROZEN BITSTREAM =========="
  print_file_record "$BITSTREAM"
  echo
  echo "========== FROZEN PAYLOAD =========="
  for path in "${PAYLOAD_FILES[@]}"; do
    print_file_record "$path"
  done
  for path in "${OPTIONAL_PAYLOAD_FILES[@]}"; do
    print_optional_file_record "$path"
  done
  echo
  echo "========== FROZEN EVIDENCE SET =========="
  for path in "${EVIDENCE_FILES[@]}"; do
    print_file_record "$path"
  done
  echo
  echo "========== FROZEN RECOVERY CHAIN =========="
  for path in "${RECOVERY_FILES[@]}"; do
    print_file_record "$path"
  done
} | tee "$OUT"

echo "P4A_BASELINE_FREEZE=$OUT"