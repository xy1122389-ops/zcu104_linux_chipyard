#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIDECAR_DIR="${ROOT_DIR}/sidecar/ceva_bt52_sidecar"
MAIN_C="${SIDECAR_DIR}/main.c"
EGRESS_C="${SIDECAR_DIR}/sidecar_event_bridge.c"

reject_pattern() {
  local file="$1"
  local pattern="$2"
  local reason="$3"

  if grep -En -- "$pattern" "$file"; then
    echo "FAIL: $reason" >&2
    exit 1
  fi

  echo "PASS: $reason"
}

require_pattern() {
  local file="$1"
  local pattern="$2"
  local reason="$3"

  if grep -Eq -- "$pattern" "$file"; then
    echo "PASS: $reason"
  else
    echo "FAIL: $reason" >&2
    exit 1
  fi
}

echo "CEVA sidecar no-synthetic-event static guard"

require_pattern "$EGRESS_C" \
  'ceva_bt52_sidecar_publish_vendor_event' \
  'gated egress helper exists'

reject_pattern "$MAIN_C" \
  'ceva_bt52_sidecar_publish_vendor_event|CEVA_BT52_BRIDGE_EVENT_READY_OFFSET|CEVA_BT52_BRIDGE_EVENT_READY_VALUE|CEVA_BT52_MARKER_OFFSET_EGRESS_EVENT_READY|CEVA_BT52_MARKER_OFFSET_HCI_SEND_2_HOST' \
  'main loop must not publish events or event-ready directly'

reject_pattern "$EGRESS_C" \
  'CEVA_BT52_HCI_OPCODE_RESET|CEVA_BT52_HCI_OPCODE_READ_LOCAL_VERSION|CEVA_BT52_HCI_RESET_EVENT_LEN|CEVA_BT52_HCI_RLV_EVENT_MIN_LEN' \
  'egress helper must not encode opcode-specific synthetic responses'

while IFS= read -r match; do
  file="${match%%:*}"
  case "$file" in
    "$EGRESS_C") ;;
    *)
      echo "$match" >&2
      echo "FAIL: event-ready writes are only allowed in sidecar_event_bridge.c" >&2
      exit 1
      ;;
  esac
done < <(grep -RIn --include='*.c' \
  -E 'CEVA_BT52_BRIDGE_EVENT_READY_OFFSET|CEVA_BT52_BRIDGE_EVENT_READY_VALUE' \
  "$SIDECAR_DIR" || true)

echo "PASS: event-ready write path is isolated to gated egress helper"
echo "H9_NO_SYNTHETIC_EVENT_GUARD=PASS"
