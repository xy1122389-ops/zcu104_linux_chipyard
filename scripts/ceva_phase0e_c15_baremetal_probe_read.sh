#!/usr/bin/env bash
# Draft-only Phase 0E-C1.5 wrapper for reading back the compiled baremetal IRQ
# probes over the stable J-Link GDB server path.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
JLINK_HOST=${JLINK_HOST:-127.0.0.1}
JLINK_PORT=${JLINK_PORT:-3333}
ELF=${ELF:-/root/chipyard/fpga/src/main/resources/zcu104/sdboot/build/sdboot.elf}

EXPECT_MAGIC=0X30454331
EXPECT_MCAUSE=0X800000000000000B
EXPECT_CLAIM_ID=0X00000001
EXPECT_PLIC_PENDING_MASK=0X00000002
EXPECT_CEVA_STATUS_MASK=0X00000008

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

echo "=== Phase 0E-C1.5 baremetal probe read draft ==="
echo "J-Link: ${JLINK_HOST}:${JLINK_PORT}"
echo "ELF    : ${ELF}"
echo ""

if [[ ! -f "$ELF" ]]; then
    echo "ERROR: sdboot ELF not found at ${ELF}"
    echo "       Rebuild only with: make -C src/main/resources/zcu104/sdboot RISCV=/root/chipyard/.oclaw-env/riscv-tools elf bin dump"
    exit 1
fi

if ! nc -z -w 3 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
    echo "[info] J-Link GDB Server is not listening on ${JLINK_HOST}:${JLINK_PORT}; starting it now..."
    bash "$SCRIPT_DIR/start_jlink_server.sh"
fi

if ! nc -z -w 3 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
    echo "ERROR: J-Link GDB Server is still not listening on ${JLINK_HOST}:${JLINK_PORT}"
    echo "       Check: bash scripts/start_jlink_server.sh"
    exit 1
fi

set +e
RESULT=$(timeout 120 "$GDB" \
    -q \
    -batch \
    -ex "set confirm off" \
    -ex "set pagination off" \
    -ex "file ${ELF}" \
    -ex "target remote ${JLINK_HOST}:${JLINK_PORT}" \
    -x "$SCRIPT_DIR/ceva_phase0e_c15_baremetal_probe_read.gdb" 2>&1)
GDB_RC=$?

set -e

echo "$RESULT"
echo ""

if (( GDB_RC != 0 )); then
    echo "FAIL: GDB probe read command exited with rc=${GDB_RC}"
    exit "$GDB_RC"
fi

PROBE_MAGIC=$(extract_value PROBE_MAGIC)
PROBE_MCAUSE=$(extract_value PROBE_MCAUSE)
PROBE_MEPC=$(extract_value PROBE_MEPC)
PROBE_MTVAL=$(extract_value PROBE_MTVAL)
PROBE_CLAIM_ID=$(extract_value PROBE_CLAIM_ID)
PROBE_PLIC_PENDING_BEFORE_CLAIM=$(extract_value PROBE_PLIC_PENDING_BEFORE_CLAIM)
PROBE_PLIC_PENDING_AFTER_ACK=$(extract_value PROBE_PLIC_PENDING_AFTER_ACK)
PROBE_CEVA_STATUS_BEFORE_ACK=$(extract_value PROBE_CEVA_STATUS_BEFORE_ACK)
PROBE_CEVA_STATUS_AFTER_ACK=$(extract_value PROBE_CEVA_STATUS_AFTER_ACK)
PROBE_COMPLETION_WRITTEN=$(extract_value PROBE_COMPLETION_WRITTEN)
PROBE_HANDLER_COUNT=$(extract_value PROBE_HANDLER_COUNT)
PROBE_TARGET_COUNT=$(extract_value PROBE_TARGET_COUNT)
PROBE_DONE=$(extract_value PROBE_DONE)
PROBE_TIMEOUT=$(extract_value PROBE_TIMEOUT)

if [[ -z "$PROBE_MAGIC" || -z "$PROBE_MCAUSE" || -z "$PROBE_CLAIM_ID" || -z "$PROBE_CEVA_STATUS_BEFORE_ACK" || -z "$PROBE_CEVA_STATUS_AFTER_ACK" || -z "$PROBE_HANDLER_COUNT" || -z "$PROBE_TARGET_COUNT" || -z "$PROBE_DONE" ]]; then
    echo "FAIL: could not parse one or more hard-pass probe values from GDB output"
    exit 1
fi

HARD_PASS=1

echo "=== hard-pass checks ==="
echo "policy: pending/completion/timeout are observation-only in C1.6"

if [[ "$PROBE_MAGIC" != "$EXPECT_MAGIC" ]]; then
    echo "FAIL: PROBE_MAGIC expected ${EXPECT_MAGIC} but got ${PROBE_MAGIC}"
    HARD_PASS=0
fi

if [[ "$PROBE_MCAUSE" != "$EXPECT_MCAUSE" ]]; then
    echo "FAIL: PROBE_MCAUSE expected ${EXPECT_MCAUSE} but got ${PROBE_MCAUSE}"
    HARD_PASS=0
fi

if [[ "$PROBE_CLAIM_ID" != "$EXPECT_CLAIM_ID" ]]; then
    echo "FAIL: PROBE_CLAIM_ID expected ${EXPECT_CLAIM_ID} but got ${PROBE_CLAIM_ID}"
    HARD_PASS=0
fi

if (( $(hex_to_dec "$PROBE_DONE") == 0 )); then
    echo "FAIL: PROBE_DONE is still zero"
    HARD_PASS=0
fi

if (( $(hex_to_dec "$PROBE_TARGET_COUNT") == 0 )); then
    echo "FAIL: PROBE_TARGET_COUNT is still zero"
    HARD_PASS=0
fi

if (( $(hex_to_dec "$PROBE_HANDLER_COUNT") != $(hex_to_dec "$PROBE_TARGET_COUNT") )); then
    echo "FAIL: PROBE_HANDLER_COUNT expected ${PROBE_TARGET_COUNT} but got ${PROBE_HANDLER_COUNT}"
    HARD_PASS=0
fi

if (( ($(hex_to_dec "$PROBE_CEVA_STATUS_BEFORE_ACK") & $(hex_to_dec "$EXPECT_CEVA_STATUS_MASK")) == 0 )); then
    echo "FAIL: PROBE_CEVA_STATUS_BEFORE_ACK does not contain bit 3"
    HARD_PASS=0
fi

if (( ($(hex_to_dec "$PROBE_CEVA_STATUS_AFTER_ACK") & $(hex_to_dec "$EXPECT_CEVA_STATUS_MASK")) != 0 )); then
    echo "FAIL: PROBE_CEVA_STATUS_AFTER_ACK still contains bit 3"
    HARD_PASS=0
fi

echo "=== observation-only fields ==="
echo "OBSERVE: PROBE_TARGET_COUNT=${PROBE_TARGET_COUNT}"
if [[ -n "$PROBE_PLIC_PENDING_BEFORE_CLAIM" ]]; then
    echo "OBSERVE: PROBE_PLIC_PENDING_BEFORE_CLAIM=${PROBE_PLIC_PENDING_BEFORE_CLAIM}"
    if (( ($(hex_to_dec "$PROBE_PLIC_PENDING_BEFORE_CLAIM") & $(hex_to_dec "$EXPECT_PLIC_PENDING_MASK")) == 0 )); then
        echo "OBSERVE: source bit 1 was not visible in PROBE_PLIC_PENDING_BEFORE_CLAIM at this sample point"
    fi
else
    echo "OBSERVE: PROBE_PLIC_PENDING_BEFORE_CLAIM unavailable"
fi

if [[ -n "$PROBE_PLIC_PENDING_AFTER_ACK" ]]; then
    echo "OBSERVE: PROBE_PLIC_PENDING_AFTER_ACK=${PROBE_PLIC_PENDING_AFTER_ACK}"
    if (( ($(hex_to_dec "$PROBE_PLIC_PENDING_AFTER_ACK") & $(hex_to_dec "$EXPECT_PLIC_PENDING_MASK")) != 0 )); then
        echo "OBSERVE: source bit 1 remained visible in PROBE_PLIC_PENDING_AFTER_ACK at this sample point"
    fi
else
    echo "OBSERVE: PROBE_PLIC_PENDING_AFTER_ACK unavailable"
fi

if [[ -n "$PROBE_COMPLETION_WRITTEN" ]]; then
    echo "OBSERVE: PROBE_COMPLETION_WRITTEN=${PROBE_COMPLETION_WRITTEN}"
else
    echo "OBSERVE: PROBE_COMPLETION_WRITTEN unavailable"
fi

if [[ -n "$PROBE_MEPC" ]]; then
    echo "OBSERVE: PROBE_MEPC=${PROBE_MEPC}"
else
    echo "OBSERVE: PROBE_MEPC unavailable"
fi

if [[ -n "$PROBE_MTVAL" ]]; then
    echo "OBSERVE: PROBE_MTVAL=${PROBE_MTVAL}"
else
    echo "OBSERVE: PROBE_MTVAL unavailable"
fi

if [[ -n "$PROBE_TIMEOUT" ]]; then
    echo "OBSERVE: PROBE_TIMEOUT=${PROBE_TIMEOUT}"
else
    echo "OBSERVE: PROBE_TIMEOUT unavailable"
fi

if (( HARD_PASS == 0 )); then
    echo "FAIL: Phase 0E-C1.6 hard-pass probe checks observed a mismatch"
    exit 1
fi

echo "PASS: hard-pass probes show repeated machine external interrupts reaching the expected target count, with CEVA claim id, CEVA status clear across ack, and final done"
exit 0