#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
JLINK_HOST=127.0.0.1
JLINK_PORT=3333

LABELS=(
    "DM VERSION"
    "BT VERSION"
    "BLE VERSION"
)

ADDRS=(
    "0x65000004"
    "0x65000404"
    "0x65000804"
)

EXPECTEDS=(
    "0x0B000500"
    "0x0B000600"
    "0x0B001100"
)

classify_failure() {
    local raw=$1

    case "$raw" in
        "<unreadable>")
            echo "bus error / unreadable"
            ;;
        "0x00000000"|"0x000000000")
            echo "all 0"
            ;;
        "0xffffffff"|"0xFFFFFFFF")
            echo "all F"
            ;;
        *)
            echo "other value"
            ;;
    esac
}

echo "=== Phase 0B-S2 CEVA 多寄存器读取 ==="
echo "J-Link: ${JLINK_HOST}:${JLINK_PORT}"
echo ""

if ! nc -z -w 3 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
    echo "[info] J-Link GDB Server 未监听 ${JLINK_HOST}:${JLINK_PORT}，自动启动 Phase0b J-Link 流程..."
    bash "$SCRIPT_DIR/phase0b_start_jlink.sh"
fi

if ! nc -z -w 3 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
    echo "ERROR: J-Link GDB Server 仍未监听 ${JLINK_HOST}:${JLINK_PORT}"
    echo "       请先检查: bash scripts/phase0b_start_jlink.sh"
    exit 1
fi

RESULT=$(timeout 30 "$GDB" -q -batch \
    -ex "set remotetimeout 15" \
    -ex "target remote ${JLINK_HOST}:${JLINK_PORT}" \
    -ex "monitor halt" \
    -ex "x/1wx ${ADDRS[0]}" \
    -ex "x/1wx ${ADDRS[1]}" \
    -ex "x/1wx ${ADDRS[2]}" \
    -ex "monitor go" \
    -ex "detach" \
    2>&1)

echo "$RESULT"
echo ""

overall_pass=1

for index in "${!ADDRS[@]}"; do
    label=${LABELS[$index]}
    addr=${ADDRS[$index]}
    expected=${EXPECTEDS[$index]}
    raw=$(printf '%s\n' "$RESULT" | awk -v addr="$addr" '$1 == addr":" { print $2; exit }')

    if [[ -z "$raw" ]]; then
        raw="<unreadable>"
    fi

    normalized_raw=$(printf '%s' "$raw" | tr '[:lower:]' '[:upper:]')
    normalized_expected=$(printf '%s' "$expected" | tr '[:lower:]' '[:upper:]')

    echo "${label}:"
    echo "  地址: ${addr}"
    echo "  实际: ${raw}"
    echo "  期望: ${expected}"

    if [[ "$normalized_raw" == "$normalized_expected" ]]; then
        echo "  结果: PASS"
    else
        overall_pass=0
        echo "  结果: FAIL ($(classify_failure "$raw"))"
    fi

    echo ""
done

if [[ $overall_pass -eq 1 ]]; then
    echo "PASS: Phase 0B-S2 CEVA multi-register read passed"
    exit 0
fi

echo "FAIL: Phase 0B-S2 CEVA multi-register read failed"
exit 1