#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_CONTRACT="${ROOT_DIR}/scripts/ceva_runtime_launch_contract.sh"
MEMORY_CONTRACT="${ROOT_DIR}/scripts/ceva_reserved_memory_contract.sh"
PHASE2_RUNNER="${ROOT_DIR}/run_phase2_ceva_bt_linux.sh"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing Linux reserved-memory e2e input: $path" >&2
    exit 1
  fi
}

log_contains_text() {
  local needle="$1"
  local file="$2"

  grep -Fq "$needle" "$file"
}

require_log_text() {
  local needle="$1"
  local file="$2"

  if ! log_contains_text "$needle" "$file"; then
    echo "FAIL: missing '$needle' in $file" >&2
    tail -n 120 "$file" >&2 || true
    exit 1
  fi
}

validate_log() {
  local file="$1"
  local expected_reserved_line
  local needle
  local required_markers=(
    "PHASE25_USER_HCI_RESET_PASS"
    "PHASE25_USER_HCI_RLV_PASS"
    "PHASE25_USER_SMOKE_PASS"
    "CEVA_PHASE25_HCI_RESET_PASS"
    "CEVA_PHASE25_READ_LOCAL_VERSION_PASS"
    "CEVA_PHASE25_SELFTEST_PASS"
    "[boot-owner] claimed=yes"
  )

  for needle in "${required_markers[@]}"; do
    if ! log_contains_text "$needle" "$file"; then
      echo "FAIL: missing '$needle' in $file" >&2
      tail -n 120 "$file" >&2 || true
      return 1
    fi
  done

  printf -v expected_reserved_line '[boot-owner] reserved_start=0x%016X reserved_size=0x%016X' "$((CEVA_RUNTIME_RESERVED_START))" "$((CEVA_RUNTIME_RESERVED_SIZE))"
  if ! log_contains_text "$expected_reserved_line" "$file"; then
    echo "FAIL: missing '$expected_reserved_line' in $file" >&2
    tail -n 120 "$file" >&2 || true
    return 1
  fi

  if grep -Eq 'Kernel panic|Oops|Segmentation fault|Reserved memory: failed to reserve memory|overlaps with ceva_runtime_reserved|ceva_runtime_reserved.*overlaps with' "$file"; then
    echo "FAIL: Linux reserved-memory e2e log contains failure markers: $file" >&2
    tail -n 120 "$file" >&2 || true
    return 1
  fi

  if grep -E 'PHASE25_USER_(HCI_RESET|HCI_RLV|SMOKE)_FAIL|CEVA_PHASE25_(HCI_RESET|READ_LOCAL_VERSION|SELFTEST)_FAIL' "$file" | grep -Ev ': MISSING' | grep -q .; then
    echo "FAIL: Linux reserved-memory e2e log contains failure markers: $file" >&2
    tail -n 120 "$file" >&2 || true
    return 1
  fi

  return 0
}

is_retryable_launch_failure() {
  local file="$1"

  log_contains_text "[boot-owner] claimed=yes" "$file" && \
  log_contains_text "[klog] runtime log_buf non-zero bytes=0" "$file" && \
  grep -Fq "[opensbi] debug_stage=0x0000000000005002" "$file"
}

source "$RUNTIME_CONTRACT"
source "$MEMORY_CONTRACT"

require_file "$RUNTIME_CONTRACT"
require_file "$MEMORY_CONTRACT"
require_file "$PHASE2_RUNNER"

LOG_PATH="${PHASE4C6_LOG_PATH:-}"
if [[ -z "$LOG_PATH" ]]; then
  MAX_ATTEMPTS="${PHASE4C6_MAX_ATTEMPTS:-3}"
  ATTEMPT=1
  FORCE_DDR_INIT_AFTER_RETRY=0

  while (( ATTEMPT <= MAX_ATTEMPTS )); do
    RUN_TAG="${PHASE4C6_RUN_TAG:-phase4c6_$(date +%Y%m%d_%H%M%S)}"
    LOG_DIR="${ROOT_DIR}/logs/${RUN_TAG}"
    LOG_PATH="${LOG_DIR}/run.log"
    SKIP_DDR_INIT_THIS="${PHASE4C6_SKIP_DDR_INIT:-1}"

    if (( FORCE_DDR_INIT_AFTER_RETRY )); then
      SKIP_DDR_INIT_THIS=0
    fi

    mkdir -p "$LOG_DIR"

    env \
      SKIP_DDR_INIT="$SKIP_DDR_INIT_THIS" \
      JLINK_HOST="${JLINK_HOST:-127.0.0.1}" \
      JLINK_PORT="${JLINK_PORT:-3333}" \
      KERNEL_RUN_SECS="${PHASE4C6_KERNEL_RUN_SECS:-120}" \
      RUN_TAG="$RUN_TAG" \
      bash "$PHASE2_RUNNER" > "$LOG_PATH" 2>&1

    require_file "$LOG_PATH"

    if validate_log "$LOG_PATH"; then
      break
    fi

    if (( ATTEMPT >= MAX_ATTEMPTS )) || ! is_retryable_launch_failure "$LOG_PATH"; then
      exit 1
    fi

    FORCE_DDR_INIT_AFTER_RETRY=1
    echo "[retry] transient launch failure detected in $LOG_PATH; retrying with DDR/PL init (${ATTEMPT}/${MAX_ATTEMPTS})" >&2
    ATTEMPT=$((ATTEMPT + 1))
  done
fi

require_file "$LOG_PATH"
validate_log "$LOG_PATH"

echo "CEVA Linux reserved-memory end-to-end"
echo "log=${LOG_PATH}"
echo "launch_owner=${CEVA_RUNTIME_LAUNCH_OWNER_CURRENT}"
echo "payload_bootstrap=${CEVA_RUNTIME_PAYLOAD_BOOTSTRAP_CURRENT}"
echo "reserved=${CEVA_RUNTIME_RESERVED_START}..${CEVA_RUNTIME_RESERVED_END} size=${CEVA_RUNTIME_RESERVED_SIZE}"
echo "P4C_LINUX_RESERVED_MEMORY_E2E=PASS"
echo "P4C_RESERVED_MEMORY_TRANSFER=PASS"