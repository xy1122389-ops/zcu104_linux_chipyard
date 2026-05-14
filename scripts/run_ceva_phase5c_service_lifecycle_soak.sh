#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P5A_RUNNER="${ROOT_DIR}/scripts/run_ceva_phase5a_live_refresh.sh"
P5A_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase5a_live_refresh_contract.sh"
JLINK_PRECHECK="${ROOT_DIR}/scripts/jlink_precheck.gdb"
JLINK_SERVER_STARTER="${ROOT_DIR}/scripts/start_jlink_server.sh"
PHASE0B_REINIT="${ROOT_DIR}/scripts/program_phase0b_bit.sh"

RUN_TAG="${PHASE5C_RUN_TAG:-phase5c_$(date +%Y%m%d_%H%M%S)}"
SOAK_ROUNDS="${SOAK_ROUNDS:-3}"
BASE_LOG_DIR="${PHASE5C_LOG_DIR:-${ROOT_DIR}/logs/${RUN_TAG}}"
BASE_REPORT_DIR="${PHASE5C_REPORT_DIR:-${ROOT_DIR}/reports/${RUN_TAG}}"
SUMMARY_PATH="${PHASE5C_SUMMARY_PATH:-${BASE_REPORT_DIR}/SUMMARY.txt}"
JLINK_HOST="${JLINK_HOST:-127.0.0.1}"
JLINK_PORT="${JLINK_PORT:-3333}"
KERNEL_RUN_SECS="${PHASE5C_KERNEL_RUN_SECS:-180}"
SKIP_DDR_INIT="${PHASE5C_SKIP_DDR_INIT:-1}"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing Phase5-C run input: $path" >&2
    exit 1
  fi
}

summary_line() {
  echo "$1" >>"$SUMMARY_PATH"
}

cleanup_stale_debug_tools() {
  pkill -f 'gdb-multiarch.*jlink_precheck\.gdb|gdb-multiarch|riscv64-unknown-elf-gdb' 2>/dev/null || true
}

ensure_jlink_ready() {
  local log_path="$1"

  cleanup_stale_debug_tools

  {
    echo "[p5c] ensuring J-Link server on ${JLINK_HOST}:${JLINK_PORT}"
    bash "$JLINK_SERVER_STARTER"
    echo "[p5c] running minimal J-Link precheck"
    gdb-multiarch -q -batch -x "$JLINK_PRECHECK"
  } >>"$log_path" 2>&1
}

recover_jlink_target() {
  local log_path="$1"

  cleanup_stale_debug_tools

  {
    echo "[p5c] J-Link recovery SOP start"
    bash "$PHASE0B_REINIT"
    echo "[p5c] forcing J-Link server restart"
    JLINK_FORCE_RESTART=1 bash "$JLINK_SERVER_STARTER"
    echo "[p5c] running post-reinit minimal J-Link precheck"
    gdb-multiarch -q -batch -x "$JLINK_PRECHECK"
    echo "[p5c] J-Link recovery SOP complete"
  } >>"$log_path" 2>&1
}

run_phase5a_attempt() {
  local round_tag="$1"
  local round_log_dir="$2"
  local round_log_path="$3"
  local round_bundle_dir="$4"

  PHASE5A_RUN_TAG="$round_tag" \
  PHASE5A_LOG_DIR="$round_log_dir" \
  PHASE5A_LOG_PATH="$round_log_path" \
  PHASE5A_BUNDLE_DIR="$round_bundle_dir" \
  PHASE5A_KERNEL_RUN_SECS="$KERNEL_RUN_SECS" \
  PHASE5A_SKIP_DDR_INIT="$SKIP_DDR_INIT" \
  JLINK_HOST="$JLINK_HOST" \
  JLINK_PORT="$JLINK_PORT" \
    bash "$P5A_RUNNER"
}

classify_failure() {
  local log_path="$1"
  local bundle_dir="$2"

  if [[ ! -f "$log_path" ]]; then
    echo "BLOCKED_BY_PHASE5A_RUNNER"
    return
  fi

  if grep -Eiq 'ERROR in source psu_init\.tcl|couldn.t read file .*psu_init\.tcl|missing psu_init\.tcl|\[stable_init\] FAILED|FAILED: hw_server did not start' "$log_path"; then
    echo "BLOCKED_BY_INIT"
  elif ! grep -Fq 'PHASE4G_SERVICE_MANAGED_RUN_DONE' "$log_path"; then
    if grep -Eiq 'Connection reset|Connection refused|Waiting for GDB connection|Could not connect|Could not select J-Link|remote connection|No present J-Link device|J-Link disappeared|GDB Server.*(not|failed)|PRECHECK FAILED' "$log_path"; then
      echo "BLOCKED_BY_JLINK_SERVER"
    else
      echo "BLOCKED_BY_PHASE5A_RUNNER"
    fi
  elif grep -Eiq 'Connection reset|Connection refused|Waiting for GDB connection|Could not connect|Could not select J-Link|remote connection|No present J-Link device|J-Link disappeared|GDB Server.*(not|failed)|PRECHECK FAILED' "$log_path"; then
    echo "BLOCKED_BY_CAPTURE"
  elif grep -Eiq 'CEVA BT5\.2 registered as hci0|ceva_bt_open: OK|PHASE25_USER_HCI_RESET_PASS|PHASE25_USER_HCI_RLV_PASS|PHASE25_USER_SMOKE_PASS' "$log_path"; then
    if [[ ! -f "${bundle_dir}/SUMMARY.txt" || ! -f "${bundle_dir}/proof_run.log" ]]; then
      echo "BLOCKED_BY_BUNDLE_COLLECTION"
    else
      echo "FAIL"
    fi
  elif grep -Fq '=== PRECHECK PASSED ===' "$log_path"; then
    echo "BLOCKED_BY_CAPTURE"
  else
    echo "FAIL"
  fi
}

validate_round() {
  local log_path="$1"
  local bundle_dir="$2"

  [[ -f "$log_path" ]] || return 1
  [[ -d "$bundle_dir" ]] || return 1
  [[ -f "${bundle_dir}/SUMMARY.txt" ]] || return 1
  [[ -f "${bundle_dir}/proof_run.log" ]] || return 1

  PHASE5A_LOG_PATH="$log_path" \
  PHASE5A_BUNDLE_DIR="$bundle_dir" \
    bash "$P5A_CHECKER" >/dev/null
}

finalized=0
current_round=0
current_round_done=0
current_round_status=""

finalize_summary() {
  local exit_rc="$1"

  if [[ "$finalized" -eq 1 ]]; then
    return
  fi
  finalized=1

  if [[ "$current_round" -gt 0 && "$current_round_done" -eq 0 ]]; then
    current_round_status="${current_round_status:-FAIL}"
    summary_line "ROUND_${current_round}_STATUS=${current_round_status}"
    summary_line "ROUND_${current_round}_BLOCKED=runner_exit_rc_${exit_rc}"
  fi

  summary_line "ATTEMPTED_ROUNDS=${attempted_rounds}"
  summary_line "SUCCESSFUL_ROUNDS=${successful_rounds}"
  summary_line "OVERALL_STATUS=${overall_status}"
  summary_line "PHASE5C_SUMMARY_PATH=${SUMMARY_PATH}"
  summary_line "PHASE5C_SERVICE_LIFECYCLE_SOAK_RUN_DONE"
}

on_exit() {
  local exit_rc=$?
  finalize_summary "$exit_rc"
}

require_file "$P5A_RUNNER"
require_file "$P5A_CHECKER"
require_file "$JLINK_PRECHECK"
require_file "$JLINK_SERVER_STARTER"
require_file "$PHASE0B_REINIT"
mkdir -p "$BASE_LOG_DIR" "$BASE_REPORT_DIR"

overall_status="PASS"
successful_rounds=0
attempted_rounds=0

{
  echo "CEVA Phase5-C service lifecycle soak"
  echo "run_tag=${RUN_TAG}"
  echo "soak_rounds=${SOAK_ROUNDS}"
  echo "jlink=${JLINK_HOST}:${JLINK_PORT}"
  echo "kernel_run_secs=${KERNEL_RUN_SECS}"
  echo "skip_ddr_init=${SKIP_DDR_INIT}"
  echo "PHASE5C_SERVICE_LIFECYCLE_SOAK_RUN_START"
} >"$SUMMARY_PATH"

trap on_exit EXIT

round=1
while [[ "$round" -le "$SOAK_ROUNDS" ]]; do
  attempted_rounds="$round"
  current_round="$round"
  current_round_done=0
  round_tag="${RUN_TAG}_round${round}"
  round_log_dir="${BASE_LOG_DIR}/round_${round}"
  round_log_path="${round_log_dir}/run.log"
  round_bundle_dir="${BASE_REPORT_DIR}/round_${round}_observability"
  round_status="PASS"
  round_rc=0
  attempt_1_status="NOT_RUN"
  attempt_2_status="NOT_RUN"
  jlink_reinit_attempted="NO"
  recovered_by_jlink_reinit="NO"
  jlink_preamble_log="${round_log_dir}/jlink_preamble.log"
  jlink_recovery_log="${round_log_dir}/jlink_recovery.log"

  mkdir -p "$round_log_dir" "$round_bundle_dir"

  summary_line "ROUND_${round}_START=$(date -Is)"
  summary_line "ROUND_${round}_TAG=${round_tag}"
  summary_line "ROUND_${round}_LOG_PATH=${round_log_path}"
  summary_line "ROUND_${round}_BUNDLE_DIR=${round_bundle_dir}"
  : >"$jlink_preamble_log"
  : >"$jlink_recovery_log"

  if ! ensure_jlink_ready "$jlink_preamble_log"; then
    attempt_1_status="BLOCKED_BY_JLINK_SERVER"
  else
    if run_phase5a_attempt "$round_tag" "$round_log_dir" "$round_log_path" "$round_bundle_dir"; then
      if validate_round "$round_log_path" "$round_bundle_dir"; then
        attempt_1_status="PASS"
        round_status="PASS"
        successful_rounds=$((successful_rounds + 1))
      else
        round_rc=1
        attempt_1_status="$(classify_failure "$round_log_path" "$round_bundle_dir")"
      fi
    else
      round_rc=$?
      attempt_1_status="$(classify_failure "$round_log_path" "$round_bundle_dir")"
    fi
  fi

  if [[ "$attempt_1_status" != "PASS" && "$attempt_1_status" == "BLOCKED_BY_JLINK_SERVER" ]]; then
    jlink_reinit_attempted="YES"

    if recover_jlink_target "$jlink_recovery_log" && run_phase5a_attempt "$round_tag" "$round_log_dir" "$round_log_path" "$round_bundle_dir"; then
      if validate_round "$round_log_path" "$round_bundle_dir"; then
        attempt_2_status="PASS"
        recovered_by_jlink_reinit="YES"
        round_status="PASS"
        round_rc=0
        successful_rounds=$((successful_rounds + 1))
      else
        round_rc=1
        attempt_2_status="$(classify_failure "$round_log_path" "$round_bundle_dir")"
        round_status="$attempt_2_status"
      fi
    else
      if [[ -f "$round_log_path" ]]; then
        attempt_2_status="$(classify_failure "$round_log_path" "$round_bundle_dir")"
      else
        attempt_2_status="BLOCKED_BY_JLINK_SERVER"
      fi
      round_status="$attempt_2_status"
    fi
  elif [[ "$attempt_1_status" != "PASS" ]]; then
    round_status="$attempt_1_status"
  fi

  summary_line "ROUND_${round}_ATTEMPT_1_STATUS=${attempt_1_status}"
  summary_line "ROUND_${round}_JLINK_REINIT_ATTEMPTED=${jlink_reinit_attempted}"
  summary_line "ROUND_${round}_RECOVERED_BY_JLINK_REINIT=${recovered_by_jlink_reinit}"
  summary_line "ROUND_${round}_ATTEMPT_2_STATUS=${attempt_2_status}"
  current_round_status="$round_status"
  summary_line "ROUND_${round}_STATUS=${round_status}"
  summary_line "ROUND_${round}_RC=${round_rc}"

  if [[ "$round_status" == "PASS" ]]; then
    summary_line "ROUND_${round}_CHECKER_RESULT=PASS"
    summary_line "ROUND_${round}_DONE=$(date -Is)"
  elif [[ "$round_status" == BLOCKED_* ]]; then
    summary_line "ROUND_${round}_CHECKER_RESULT=${round_status}"
    summary_line "ROUND_${round}_BLOCKED=$(date -Is)"
  else
    summary_line "ROUND_${round}_CHECKER_RESULT=FAIL"
    summary_line "ROUND_${round}_FAIL=$(date -Is)"
  fi
  current_round_done=1

  if [[ "$round_status" != "PASS" ]]; then
    overall_status="$round_status"
    break
  fi

  round=$((round + 1))
done

echo "PHASE5C_SUMMARY_PATH=${SUMMARY_PATH}"

if [[ "$successful_rounds" -ne "$SOAK_ROUNDS" ]]; then
  exit 1
fi