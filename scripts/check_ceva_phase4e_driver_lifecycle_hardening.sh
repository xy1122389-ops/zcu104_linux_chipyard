#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVER_C="${ROOT_DIR}/linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c"
PHASE4B_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4b_runtime_launch_contract.sh"
PHASE4D_CHECKER="${ROOT_DIR}/scripts/check_ceva_phase4d_vendor_build_reproducibility.sh"
DEFAULT_PROOF_LOG="${ROOT_DIR}/logs/phase4c6_20260513_230221/run.log"
PROOF_LOG="${PHASE4E_LOG_PATH:-${PHASE4C6_LOG_PATH:-$DEFAULT_PROOF_LOG}}"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing P4-E input: $path" >&2
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
    echo "FAIL: unexpected P4-E runtime failure evidence in $file" >&2
    echo "$matches" >&2
    exit 1
  fi
}

require_file "$DRIVER_C"
require_file "$PHASE4B_CHECKER"
require_file "$PHASE4D_CHECKER"
require_file "$PROOF_LOG"

bash "$PHASE4B_CHECKER" >/dev/null
bash "$PHASE4D_CHECKER" >/dev/null

require_text "static bool phase25_selftest = false;" "$DRIVER_C"
require_text "platform_get_resource(pdev, IORESOURCE_MEM, 0)" "$DRIVER_C"
require_text "platform_get_irq(pdev, 0)" "$DRIVER_C"
require_text "devm_ioremap(&pdev->dev, base_phys, CEVA_REG_SIZE + CEVA_EM_SIZE)" "$DRIVER_C"
require_text "spin_lock_init(&cbt->lock)" "$DRIVER_C"
require_text "INIT_WORK(&cbt->rx_work, ceva_bt_rx_work)" "$DRIVER_C"
require_text "INIT_WORK(&cbt->phase25_rsp_work, ceva_bt_phase25_rsp_work)" "$DRIVER_C"
require_text "INIT_DELAYED_WORK(&cbt->phase25_selftest_work, ceva_bt_phase25_selftest)" "$DRIVER_C"
require_text "INIT_DELAYED_WORK(&cbt->evt_recheck_work, ceva_bt_evt_recheck_work)" "$DRIVER_C"
require_text "skb_queue_head_init(&cbt->rx_queue)" "$DRIVER_C"
require_text "hci_alloc_dev()" "$DRIVER_C"
require_text "hci_register_dev(hdev)" "$DRIVER_C"
require_text "hci_unregister_dev(cbt->hdev)" "$DRIVER_C"
require_text "hci_free_dev(cbt->hdev)" "$DRIVER_C"
require_text "cancel_delayed_work_sync(&cbt->phase25_selftest_work)" "$DRIVER_C"
require_text "cancel_delayed_work_sync(&cbt->evt_recheck_work)" "$DRIVER_C"
require_text "cancel_work_sync(&cbt->phase25_rsp_work)" "$DRIVER_C"
require_text "cancel_work_sync(&cbt->rx_work)" "$DRIVER_C"
require_text "skb_queue_purge(&cbt->rx_queue)" "$DRIVER_C"
require_text "if (hci_skb_pkt_type(skb) != HCI_COMMAND_PKT)" "$DRIVER_C"
require_text "if (len + 1 > sizeof(words))" "$DRIVER_C"
require_text "if (buf[0] != HCI_EVENT_PKT)" "$DRIVER_C"
require_text "if (len > sizeof(words))" "$DRIVER_C"
require_text "ceva_bt_arm_evt_recheck(cbt, CEVA_BT_EVT_RECHECK_TRIES)" "$DRIVER_C"
require_text "CEVA_BT_EVT_RECHECK_TRIES" "$DRIVER_C"

require_text "CEVA BT5.2 registered as hci0" "$PROOF_LOG"
require_text "ceva_bt_open: OK" "$PROOF_LOG"
require_text "BT core running (CLKN 5/5 OK)" "$PROOF_LOG"
require_text "CEVA_PHASE25_OPEN_REACHED: SET" "$PROOF_LOG"
require_text "PHASE25_USER_HCI_RESET_PASS" "$PROOF_LOG"
require_text "PHASE25_USER_HCI_RLV_PASS" "$PROOF_LOG"
require_text "PHASE25_USER_SMOKE_PASS" "$PROOF_LOG"
require_text "CEVA_PHASE25_SELFTEST_PASS: PASS" "$PROOF_LOG"
require_absent_regex 'Kernel panic|Oops|BUG:|Unable to handle|CEVA_PHASE25_.*_FAIL|PHASE25_USER_.*_FAIL' "$PROOF_LOG"

echo "CEVA Phase4-E driver lifecycle hardening"
echo "driver=${DRIVER_C}"
echo "proof_log=${PROOF_LOG}"
echo "P4E_DRIVER_LIFECYCLE_HARDENING=PASS"
echo "P4E_PROBE_REGISTER_LIFECYCLE=PASS"
echo "P4E_OPEN_CLOSE_CLEANUP=PASS"
echo "P4E_SEND_RX_BOUNDS_RECHECK=PASS"
echo "P4E_PHASE25_SYNTHETIC_DEFAULT_OFF=PASS"
echo "P4E_RUNTIME_HCI_SMOKE_PROOF=PASS"