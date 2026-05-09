#!/usr/bin/env bash
# Draft-only Phase 0E-B2 validation wrapper for the single dm_sw_irq path.
#
# The default PLIC-side values below are derived from generated collateral for
# RocketZCU104Phase0bConfig:
#   - CEVA source id 1
#   - PLIC base 0x0c000000
#   - pending_1 at 0x0c001000 bit 1
#   - enables_0 at 0x0c002000 bit 1
#   - priority_1 at 0x0c000004
#   - threshold_0 at 0x0c200000
#   - claim_complete_0 at 0x0c200004

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
JLINK_HOST=${JLINK_HOST:-127.0.0.1}
JLINK_PORT=${JLINK_PORT:-3333}

CEVA_TRIGGER_ADDR=0x65000000
CEVA_MASK_ADDR=0x65000018
CEVA_STATUS_ADDR=0x6500001c
CEVA_ACK_ADDR=0x65000020

CEVA_STATUS_BIT_MASK=0x00000008

CEVA_PLIC_SOURCE_ID=${CEVA_PLIC_SOURCE_ID:-1}
PLIC_BASE=${PLIC_BASE:-0x0c000000}
PLIC_PENDING_ADDR=${PLIC_PENDING_ADDR:-0x0c001000}
PLIC_PENDING_BIT=${PLIC_PENDING_BIT:-1}
PLIC_ENABLE_ADDR=${PLIC_ENABLE_ADDR:-0x0c002000}
PLIC_ENABLE_BIT=${PLIC_ENABLE_BIT:-1}
PLIC_PRIORITY_ADDR=${PLIC_PRIORITY_ADDR:-0x0c000004}
PLIC_THRESHOLD_ADDR=${PLIC_THRESHOLD_ADDR:-0x0c200000}
PLIC_CLAIM_COMPLETE_ADDR=${PLIC_CLAIM_COMPLETE_ADDR:-0x0c200004}

extract_value() {
    local key=$1
    local value

    value=$(printf '%s\n' "$RESULT" | awk -F= -v key="$key" '$1 == key { print $2; exit }')
    if [[ -z "$value" ]]; then
        echo ""
        return
    fi
    printf '%s' "$value" | tr '[:lower:]' '[:upper:]'
}

hex_to_dec() {
    local value=$1
    printf '%u' "$((value))"
}

bit_to_mask_hex() {
    local bit=$1
    printf '0x%08X' "$((1 << bit))"
}

PLIC_PENDING_BIT_MASK=$(bit_to_mask_hex "$PLIC_PENDING_BIT")
PLIC_ENABLE_BIT_MASK=$(bit_to_mask_hex "$PLIC_ENABLE_BIT")

echo "=== Phase 0E-B2 dm_sw_irq J-Link draft ==="
echo "J-Link: ${JLINK_HOST}:${JLINK_PORT}"
echo "trigger addr : ${CEVA_TRIGGER_ADDR}"
echo "mask addr    : ${CEVA_MASK_ADDR}"
echo "status addr  : ${CEVA_STATUS_ADDR}"
echo "ack addr     : ${CEVA_ACK_ADDR}"
echo "PLIC base    : ${PLIC_BASE}"
echo "PLIC source  : ${CEVA_PLIC_SOURCE_ID}"
echo "PLIC pending : ${PLIC_PENDING_ADDR} bit ${PLIC_PENDING_BIT} mask ${PLIC_PENDING_BIT_MASK}"
echo "PLIC enable  : ${PLIC_ENABLE_ADDR} bit ${PLIC_ENABLE_BIT} mask ${PLIC_ENABLE_BIT_MASK}"
echo "PLIC prio    : ${PLIC_PRIORITY_ADDR}"
echo "PLIC thresh  : ${PLIC_THRESHOLD_ADDR}"
echo "PLIC claim   : ${PLIC_CLAIM_COMPLETE_ADDR}"
echo ""

if ! nc -z -w 3 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
    echo "[info] J-Link GDB Server is not listening on ${JLINK_HOST}:${JLINK_PORT}; starting it now..."
    bash "$SCRIPT_DIR/start_jlink_server.sh"
fi

if ! nc -z -w 3 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
    echo "ERROR: J-Link GDB Server is still not listening on ${JLINK_HOST}:${JLINK_PORT}"
    echo "       Check: bash scripts/start_jlink_server.sh"
    exit 1
fi

GDB_ARGS=(
    -q
    -batch
    -ex "set confirm off"
    -ex "set pagination off"
    -ex "target remote ${JLINK_HOST}:${JLINK_PORT}"
    -ex "set \$ceva_plic_source_id = ${CEVA_PLIC_SOURCE_ID}"
    -ex "set \$plic_base = ${PLIC_BASE}"
    -ex "set \$plic_pending_addr = ${PLIC_PENDING_ADDR}"
    -ex "set \$plic_pending_bit = ${PLIC_PENDING_BIT}"
    -ex "set \$plic_enable_addr = ${PLIC_ENABLE_ADDR}"
    -ex "set \$plic_enable_bit = ${PLIC_ENABLE_BIT}"
    -ex "set \$plic_priority_addr = ${PLIC_PRIORITY_ADDR}"
    -ex "set \$plic_threshold_addr = ${PLIC_THRESHOLD_ADDR}"
    -ex "set \$plic_claim_complete_addr = ${PLIC_CLAIM_COMPLETE_ADDR}"
)

GDB_ARGS+=(
    -ex "set \$have_plic_pending = 1"
)

GDB_ARGS+=(-x "$SCRIPT_DIR/ceva_phase0e_b2_dm_sw_irq_jlink.gdb")

RESULT=$(timeout 60 "$GDB" "${GDB_ARGS[@]}" 2>&1)

echo "$RESULT"
echo ""

STATUS_BASELINE=$(extract_value STATUS_BASELINE)
STATUS_AFTER_TRIGGER=$(extract_value STATUS_AFTER_TRIGGER)
STATUS_AFTER_ACK=$(extract_value STATUS_AFTER_ACK)

if [[ -z "$STATUS_BASELINE" || -z "$STATUS_AFTER_TRIGGER" || -z "$STATUS_AFTER_ACK" ]]; then
    echo "FAIL: could not parse the CEVA status sequence from GDB output"
    exit 1
fi

STATUS_BASELINE_DEC=$(hex_to_dec "$STATUS_BASELINE")
STATUS_AFTER_TRIGGER_DEC=$(hex_to_dec "$STATUS_AFTER_TRIGGER")
STATUS_AFTER_ACK_DEC=$(hex_to_dec "$STATUS_AFTER_ACK")
STATUS_MASK_DEC=$(hex_to_dec "${CEVA_STATUS_BIT_MASK^^}")
PLIC_PENDING_BASELINE=$(extract_value PLIC_PENDING_BASELINE)
PLIC_PENDING_AFTER_TRIGGER=$(extract_value PLIC_PENDING_AFTER_TRIGGER)
PLIC_PENDING_AFTER_ACK=$(extract_value PLIC_PENDING_AFTER_ACK)
PLIC_PENDING_MASK_DEC=$(hex_to_dec "${PLIC_PENDING_BIT_MASK}")

LOCAL_PASS=1

if (( (STATUS_BASELINE_DEC & STATUS_MASK_DEC) != 0 )); then
    echo "FAIL: STATUS_BASELINE still has swintstat set"
    LOCAL_PASS=0
fi

if (( (STATUS_AFTER_TRIGGER_DEC & STATUS_MASK_DEC) == 0 )); then
    echo "FAIL: STATUS_AFTER_TRIGGER did not show swintstat"
    LOCAL_PASS=0
fi

if (( (STATUS_AFTER_ACK_DEC & STATUS_MASK_DEC) != 0 )); then
    echo "FAIL: STATUS_AFTER_ACK still has swintstat set"
    LOCAL_PASS=0
fi

if (( LOCAL_PASS == 0 )); then
    echo "FAIL: CEVA local dm_sw_irq one-shot sequence did not match 0 -> 1 -> 0"
    exit 1
fi

if [[ -z "$PLIC_PENDING_BASELINE" || -z "$PLIC_PENDING_AFTER_TRIGGER" || -z "$PLIC_PENDING_AFTER_ACK" ]]; then
    echo "FAIL: could not parse the PLIC pending sequence from GDB output"
    exit 1
fi

PLIC_PENDING_BASELINE_DEC=$(hex_to_dec "$PLIC_PENDING_BASELINE")
PLIC_PENDING_AFTER_TRIGGER_DEC=$(hex_to_dec "$PLIC_PENDING_AFTER_TRIGGER")
PLIC_PENDING_AFTER_ACK_DEC=$(hex_to_dec "$PLIC_PENDING_AFTER_ACK")

if (( (PLIC_PENDING_BASELINE_DEC & PLIC_PENDING_MASK_DEC) != 0 )); then
    echo "FAIL: PLIC pending baseline still has the CEVA bit set"
    exit 1
fi

if (( (PLIC_PENDING_AFTER_TRIGGER_DEC & PLIC_PENDING_MASK_DEC) == 0 )); then
    echo "FAIL: PLIC pending did not show the CEVA bit after trigger"
    exit 1
fi

if (( (PLIC_PENDING_AFTER_ACK_DEC & PLIC_PENDING_MASK_DEC) != 0 )); then
    echo "FAIL: PLIC pending still has the CEVA bit set after ack"
    exit 1
fi

echo "PASS: CEVA local status and PLIC pending bit ${PLIC_PENDING_BIT} matched the one-shot IRQ sequence"
exit 0