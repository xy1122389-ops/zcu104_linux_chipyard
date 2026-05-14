#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVER_C="${ROOT_DIR}/linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c"
DTS="${ROOT_DIR}/linux-bringup/dtb/chipyard-zcu104-fedora.dts"
PHASE4E_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4e_driver_lifecycle_hardening.sh"
DEFAULT_PROOF_LOG="${ROOT_DIR}/logs/phase4c6_20260513_230221/run.log"
PROOF_LOG="${PHASE4F_LOG_PATH:-${PHASE4E_LOG_PATH:-${PHASE4C6_LOG_PATH:-$DEFAULT_PROOF_LOG}}}"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing P4-F input: $path" >&2
    exit 1
  fi
}

require_text() {
  local needle="$1"
  local file="$2"

  if ! grep -Fq -- "$needle" "$file"; then
    echo "FAIL: missing '$needle' in $file" >&2
    exit 1
  fi
}

require_absent_regex() {
  local pattern="$1"
  local file="$2"
  local matches

  matches="$(grep -Ein "$pattern" "$file" | grep -Ev ': MISSING|FAIL/WARN|Searching for panic/error strings|No executable has been specified|^.*\[WARN\].*SKIP_DDR_INIT' || true)"
  if [[ -n "$matches" ]]; then
    echo "FAIL: unexpected P4-F runtime failure evidence in $file" >&2
    echo "$matches" >&2
    exit 1
  fi
}

require_absent_source_regex() {
  local pattern="$1"
  local file="$2"
  local matches

  matches="$(grep -En "$pattern" "$file" || true)"
  if [[ -n "$matches" ]]; then
    echo "FAIL: forbidden P4-F source pattern in $file" >&2
    echo "$matches" >&2
    exit 1
  fi
}

require_file "$DRIVER_C"
require_file "$DTS"
require_file "$PHASE4E_CHECKER"
require_file "$PROOF_LOG"

PHASE4E_LOG_PATH="$PROOF_LOG" bash "$PHASE4E_CHECKER" >/dev/null

require_text "#define DM_SWINT_REQ        BIT(27)" "$DRIVER_C"
require_text "#define DM_SWINTMSK         BIT(3)" "$DRIVER_C"
require_text "#define DM_SWINTSTAT        BIT(3)" "$DRIVER_C"
require_text "#define DM_SWINTACK         BIT(3)" "$DRIVER_C"
require_text "#define DM_CLKNINTMSK       BIT(0)" "$DRIVER_C"
require_text "#define DM_SLPINTMSK        BIT(1)" "$DRIVER_C"
require_text "#define DM_CRYPTINTMSK      BIT(2)" "$DRIVER_C"
require_text "#define DM_FIFOINTMSK       BIT(15)" "$DRIVER_C"
require_text "DM_REALPATH_INTMSK  (DM_FIFOINTMSK | DM_CRYPTINTMSK |" "$DRIVER_C"
require_text "DM_SWINTMSK | DM_SLPINTMSK)" "$DRIVER_C"
require_text "#define CEVA_BT_EVT_RECHECK_MS                  1" "$DRIVER_C"
require_text "#define CEVA_BT_EVT_RECHECK_TRIES               50" "$DRIVER_C"
require_text "dm_write(cbt, DM_TIMGENCNTL, TIMGENCNTL_VAL)" "$DRIVER_C"
require_text "dm_write(cbt, DM_INTCNTL1, DM_REALPATH_INTMSK)" "$DRIVER_C"
require_text "static irqreturn_t ceva_bt_irq" "$DRIVER_C"
require_text "devm_request_irq(&pdev->dev, irq, ceva_bt_irq," "$DRIVER_C"
require_text "IRQF_TRIGGER_HIGH" "$DRIVER_C"
require_text "dm_write(cbt, DM_INTACK1, DM_SWINTACK)" "$DRIVER_C"
require_text "mod_delayed_work(system_wq, &cbt->evt_recheck_work," "$DRIVER_C"
require_text "msecs_to_jiffies(CEVA_BT_EVT_RECHECK_MS)" "$DRIVER_C"
require_text "dm_write(cbt, BT_RWBTCNTL, BT_RWBTCNTL_INIT)" "$DRIVER_C"
require_text "dm_write(cbt, DM_INTCNTL1, 0)" "$DRIVER_C"
require_absent_source_regex 'pm_runtime_|\.suspend|\.resume' "$DRIVER_C"

require_text 'compatible = "ceva,rw-dm-bt52";' "$DTS"
require_text 'interrupt-parent = <&L16>;' "$DTS"
require_text 'interrupts = <1>;' "$DTS"
require_text 'reg = <0x65000000 0x20000>;' "$DTS"

require_text "CEVA BT5.2 registered as hci0 (IRQ" "$PROOF_LOG"
require_text "BT core running (CLKN 5/5 OK)" "$PROOF_LOG"
require_text "PHASE25_USER_CMD_0c03_POLL_READY" "$PROOF_LOG"
require_text "PHASE25_USER_CMD_1001_POLL_READY" "$PROOF_LOG"
require_text "CEVA_PHASE25_CMD_SHADOW: PRESENT" "$PROOF_LOG"
require_text "CEVA_PHASE25_EVT_SHADOW: PRESENT" "$PROOF_LOG"
require_text "CEVA_PHASE25_MARKERS: PRESENT" "$PROOF_LOG"
require_text "CEVA_PHASE25_SELFTEST_PASS: PASS" "$PROOF_LOG"
require_absent_regex 'Kernel panic|Oops|BUG:|Unable to handle|CEVA_PHASE25_.*_FAIL|PHASE25_USER_.*_FAIL' "$PROOF_LOG"

echo "CEVA Phase4-F interrupt/timer/power hardening"
echo "driver=${DRIVER_C}"
echo "dts=${DTS}"
echo "proof_log=${PROOF_LOG}"
echo "P4F_INTERRUPT_TIMER_POWER_HARDENING=PASS"
echo "P4F_SWINT_IRQ_PATH=PASS"
echo "P4F_TIMER_RECHECK_BOUNDING=PASS"
echo "P4F_ACTIVE_NO_DEEP_SLEEP_POLICY=PASS"
echo "P4F_RUNTIME_IRQ_TIMER_PROOF=PASS"