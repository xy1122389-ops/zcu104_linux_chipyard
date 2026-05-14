#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MEMORY_CONTRACT="${ROOT_DIR}/scripts/ceva_reserved_memory_contract.sh"
STATIC_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4c5_opensbi_root_domain_carveout.sh"
JLINK_GUARD="${ROOT_DIR}/scripts/jlink_guard.sh"
GDB_SCRIPT="${ROOT_DIR}/scripts/ceva_phase4c5_runtime_root_domain_proof.gdb"
FW_BIN="/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin"
FW_ELF="/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf"
DTB="${ROOT_DIR}/linux-bringup/dtb/chipyard-zcu104-fedora.dtb"
TMP_CHUNK="/tmp/phase4c5_fw_chunk_00.bin"
TMP_OUT="$(mktemp /tmp/ceva_phase4c5_runtime_root_domain_proof.XXXXXX.log)"
trap 'rm -f "$TMP_OUT"' EXIT

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing runtime root-domain proof input: $path" >&2
    exit 1
  fi
}

extract_field() {
  local pattern="$1"
  local value

  value="$(grep -E "$pattern" "$TMP_OUT" | tail -n 1 | sed -E 's/.*=([0-9]+).*/\1/')"
  if [[ -z "$value" ]]; then
    echo "FAIL: missing runtime proof field for pattern: $pattern" >&2
    tail -n 80 "$TMP_OUT" >&2 || true
    exit 1
  fi

  printf '%s\n' "$value"
}

source "$MEMORY_CONTRACT"

require_file "$MEMORY_CONTRACT"
require_file "$STATIC_CHECKER"
require_file "$JLINK_GUARD"
require_file "$GDB_SCRIPT"
require_file "$FW_BIN"
require_file "$FW_ELF"
require_file "$DTB"

bash "$STATIC_CHECKER" >/dev/null

LOG_PROOF_PATH="${PHASE4C5_LOG_PATH:-${PHASE4C6_LOG_PATH:-}}"
if [[ -n "$LOG_PROOF_PATH" ]]; then
  require_file "$LOG_PROOF_PATH"

  if ! grep -Fq '[boot-owner] claimed=yes' "$LOG_PROOF_PATH"; then
    echo "FAIL: boot-owner marker claim missing in runtime log: $LOG_PROOF_PATH" >&2
    exit 1
  fi

  printf -v expected_reserved_line '[boot-owner] reserved_start=0x%016X reserved_size=0x%016X' "$((CEVA_RUNTIME_RESERVED_START))" "$((CEVA_RUNTIME_RESERVED_SIZE))"
  if ! grep -Fq "$expected_reserved_line" "$LOG_PROOF_PATH"; then
    echo "FAIL: reserved-memory marker line missing in runtime log: $LOG_PROOF_PATH" >&2
    exit 1
  fi

  if ! grep -Fq 'OF: reserved mem:' "$LOG_PROOF_PATH" || ! grep -Fq "${CEVA_RESERVED_MEMORY_DTB_NODE}@" "$LOG_PROOF_PATH"; then
    echo "FAIL: Linux reserved-memory consumption line missing in runtime log: $LOG_PROOF_PATH" >&2
    exit 1
  fi

  if grep -Eq 'mmode_resv[0-9]+@.*overlaps with ceva_runtime_reserved|ceva_runtime_reserved@.*overlaps with mmode_resv[0-9]+' "$LOG_PROOF_PATH"; then
    echo "FAIL: OpenSBI mmode reserved-memory overlap found in runtime log: $LOG_PROOF_PATH" >&2
    exit 1
  fi

  echo "CEVA OpenSBI/Linux reserved-memory runtime proof"
  echo "runtime_log=${LOG_PROOF_PATH}"
  echo "reserved_range=${CEVA_RUNTIME_RESERVED_START}..${CEVA_RUNTIME_RESERVED_END} size=${CEVA_RUNTIME_RESERVED_SIZE}"
  echo "runtime_root_domain_carveout=disabled"
  echo "runtime_overlap_with_mmode_resv=absent"
  echo "P4C_OPENSBI_ROOT_DOMAIN_RUNTIME_PROOF=PASS"
  echo "P4C_OPENSBI_ROOT_DOMAIN_CARVEOUT_DISABLED=PASS"
  echo "P4C_LINUX_NO_MAP_OWNS_RESERVED_MEMORY=PASS"
  echo "P4C_RUNTIME_RELEASE_FROM_OPENSBI=PASS"
  exit 0
fi

JLINK_HOST="${JLINK_HOST:-127.0.0.1}"
JLINK_PORT="${JLINK_PORT:-3333}"

bash "$JLINK_GUARD" >/dev/null
dd if="$FW_BIN" of="$TMP_CHUNK" bs=1024 count=4096 status=none

PHASE4C5_FW_CHUNK0="$TMP_CHUNK" \
PHASE4C5_DTB="$DTB" \
PHASE4C5_FW_ELF="$FW_ELF" \
JLINK_HOST="$JLINK_HOST" \
JLINK_PORT="$JLINK_PORT" \
  /root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb \
  -q -batch -x "$GDB_SCRIPT" > "$TMP_OUT" 2>&1

before_count="$(extract_field 'root_memregs_count before=[0-9]+')"
after_count="$(extract_field 'root_memregs_count after=[0-9]+')"
overlap_count="$(extract_field 'reserved_overlap_regions=[0-9]+')"
flags_ok_count="$(grep -c 'overlap=CEVA_RESERVED.*flags_ok=1' "$TMP_OUT" || true)"
flags_bad_count="$(grep -c 'overlap=CEVA_RESERVED.*flags_ok=0' "$TMP_OUT" || true)"

if [[ "$before_count" != "4" ]]; then
  echo "FAIL: unexpected root_memregs_count before=$before_count" >&2
  tail -n 80 "$TMP_OUT" >&2 || true
  exit 1
fi

if [[ "$after_count" != "4" ]]; then
  echo "FAIL: unexpected root_memregs_count after=$after_count" >&2
  tail -n 80 "$TMP_OUT" >&2 || true
  exit 1
fi

if [[ "$overlap_count" != "1" ]]; then
  echo "FAIL: unexpected reserved_overlap_regions=$overlap_count" >&2
  tail -n 80 "$TMP_OUT" >&2 || true
  exit 1
fi

if [[ "$flags_ok_count" != "0" ]]; then
  echo "FAIL: unexpected flags_ok=1 overlap count=$flags_ok_count" >&2
  tail -n 80 "$TMP_OUT" >&2 || true
  exit 1
fi

if [[ "$flags_bad_count" != "1" ]]; then
  echo "FAIL: unexpected flags_ok=0 overlap count=$flags_bad_count" >&2
  tail -n 80 "$TMP_OUT" >&2 || true
  exit 1
fi

echo "CEVA OpenSBI root-domain runtime proof"
echo "fw_bin=${FW_BIN}"
echo "fw_elf=${FW_ELF}"
echo "dtb=${DTB}"
echo "runtime_before=${before_count}"
echo "runtime_after=${after_count}"
echo "runtime_overlap_regions=${overlap_count}"
echo "runtime_flags_ok_regions=${flags_ok_count}"
echo "runtime_flags_bad_regions=${flags_bad_count}"
echo "reserved_range=${CEVA_RUNTIME_RESERVED_START}..${CEVA_RUNTIME_RESERVED_END} size=${CEVA_RUNTIME_RESERVED_SIZE}"
echo "P4C_OPENSBI_ROOT_DOMAIN_RUNTIME_PROOF=PASS"
echo "P4C_OPENSBI_ROOT_DOMAIN_CARVEOUT=PASS"
echo "P4C_OPENSBI_ROOT_DOMAIN_CARVEOUT_DISABLED=PASS"
echo "P4C_LINUX_NO_MAP_OWNS_RESERVED_MEMORY=PASS"
echo "P4C_RUNTIME_RELEASE_FROM_OPENSBI=PASS"