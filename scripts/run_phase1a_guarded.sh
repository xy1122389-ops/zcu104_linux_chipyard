#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${LOG_DIR:-${SCRIPT_DIR}/../logs}"
LOG_FILE="${LOG_DIR}/phase1a_guarded_${STAMP}.log"
GDB_BIN="${GDB_BIN:-riscv64-unknown-elf-gdb}"

mkdir -p "${LOG_DIR}"
export PATH="/root/chipyard/.oclaw-env/bin:/root/chipyard/.oclaw-env/riscv-tools/bin:${PATH}"

echo "[phase1a-guarded] Log: ${LOG_FILE}"

{
    echo "[phase1a-guarded] === pre-guard ==="
    bash "${SCRIPT_DIR}/jlink_guard.sh"

    echo "[phase1a-guarded] === phase1a ==="
    set +e
    timeout 120 "${GDB_BIN}" -q -batch -x "${SCRIPT_DIR}/ceva_phase1a_jlink_em_mmio.gdb"
    PHASE1A_RC=$?
    set -e

    echo "[phase1a-guarded] === post-status ==="
    bash "${SCRIPT_DIR}/jlink_status.sh" || true

    exit "${PHASE1A_RC}"
} 2>&1 | tee "${LOG_FILE}"

if grep -q "VERDICT: PASS" "${LOG_FILE}"; then
    echo "[phase1a-guarded] PASS"
    exit 0
fi

echo "[phase1a-guarded] FAIL: Phase 1A did not reach VERDICT: PASS" >&2
exit 1