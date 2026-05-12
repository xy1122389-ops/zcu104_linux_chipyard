#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-/tmp/ceva_phase3_status_snapshot.txt}"

cd "$ROOT_DIR"

{
  echo "CEVA BT5.2 Phase3 status snapshot"
  echo "timestamp=$(date -Iseconds)"
  echo
  echo "========== git =========="
  git log -1 --oneline
  git branch --show-current
  git status --short
  echo
  echo "========== H4 memory contract =========="
  bash scripts/check_ceva_sidecar_memory_contract.sh
  echo
  echo "========== H9 no-synthetic guard =========="
  bash scripts/check_ceva_sidecar_no_synthetic_event.sh
  echo
  echo "========== Phase3 completion gate =========="
  bash scripts/check_ceva_phase3_completion_gate.sh --status
  echo
  echo "========== evidence files =========="
  find docs/bringup/phase3_completion_evidence -maxdepth 2 -type f 2>/dev/null | sort || true
} | tee "$OUT"

echo "PHASE3_STATUS_SNAPSHOT=$OUT"
