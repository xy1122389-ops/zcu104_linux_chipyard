#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
JLINK_HOST=127.0.0.1
JLINK_PORT=3333

DEBUGADDMAX_ADDR=0x65000058
DEBUGADDMIN_ADDR=0x6500005c
EM_BASE=${EM_BASE:-0x65010000}

if [[ -n "${EM_OFFSETS:-}" ]]; then
    read -r -a OFFSETS <<<"${EM_OFFSETS}"
else
    OFFSETS=(
        0x0000
        0x0004
        0x0008
        0x000c
        0x0010
        0x0020
        0x0040
        0x0100
        0x0400
        0x1000
        0x4000
        0xfffc
    )
fi

hex32() {
    printf '0x%08X' "$(( ($1) & 0xffffffff ))"
}

echo "=== Phase 0C-B CEVA EM range sweep ==="
echo "J-Link : ${JLINK_HOST}:${JLINK_PORT}"
echo "EM base : ${EM_BASE}"
echo "Offsets : ${OFFSETS[*]}"
echo ""

if ! nc -z -w 3 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
    echo "[info] J-Link GDB Server 未监听 ${JLINK_HOST}:${JLINK_PORT}，自动启动 Phase0b J-Link 流程..."
    bash "$SCRIPT_DIR/phase0b_start_jlink.sh"
fi

if ! nc -z -w 3 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
    echo "ERROR: J-Link GDB Server 仍未监听 ${JLINK_HOST}:${JLINK_PORT}"
    exit 1
fi

GDB_CMDS=$(mktemp)
trap 'rm -f "$GDB_CMDS"' EXIT

declare -a ADDRS=()
declare -a PATTERNS=()

{
    echo "set remotetimeout 20"
    echo "target remote ${JLINK_HOST}:${JLINK_PORT}"
    echo "monitor halt"
    echo "monitor WriteU32 ${DEBUGADDMAX_ADDR} 0xffffffff"
    echo "monitor WriteU32 ${DEBUGADDMIN_ADDR} 0x00000000"
    echo "x/1wx ${DEBUGADDMAX_ADDR}"
    echo "x/1wx ${DEBUGADDMIN_ADDR}"
} >"$GDB_CMDS"

for idx in "${!OFFSETS[@]}"; do
    offset=${OFFSETS[$idx]}
    addr=$(( EM_BASE + offset ))
    pattern=$(( (0xC5000000 + (idx * 0x00110011) + ((offset >> 2) & 0xffff)) & 0xffffffff ))
    ADDRS+=("$(hex32 "$addr")")
    PATTERNS+=("$(hex32 "$pattern")")
    printf 'slot[%02d] addr=%s pattern=%s\n' "$idx" "$(hex32 "$addr")" "$(hex32 "$pattern")"
    echo "monitor WriteU32 $(hex32 "$addr") $(hex32 "$pattern")" >>"$GDB_CMDS"
done

{
    for addr in "${ADDRS[@]}"; do
        echo "x/1wx ${addr}"
    done
    for addr in "${ADDRS[@]}"; do
        echo "x/1wx ${addr}"
    done
    echo "monitor go"
    echo "detach"
} >>"$GDB_CMDS"

echo ""
RESULT=$(timeout 120 "$GDB" -q -batch -x "$GDB_CMDS" 2>&1)
echo "$RESULT"
echo ""

extract_last_read() {
    local addr=$1
    local addr_lc
    addr_lc=$(printf '%s' "$addr" | tr '[:upper:]' '[:lower:]')
    printf '%s\n' "$RESULT" | awk -v addr="$addr_lc" '{ token = tolower($1); if (token == addr ":") value=$2 } END { if (value != "") print value }'
}

normalize_hex() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

PASS=1

RAW_MAX=$(extract_last_read "$DEBUGADDMAX_ADDR")
RAW_MIN=$(extract_last_read "$DEBUGADDMIN_ADDR")

echo "DEBUGADDMAX readback: ${RAW_MAX:-<unreadable>}"
echo "DEBUGADDMIN readback: ${RAW_MIN:-<unreadable>}"

if [[ "$(normalize_hex "${RAW_MAX:-}")" != "0XFFFFFFFF" ]]; then
    echo "FAIL: DEBUGADDMAX 未成功打开到 0xffff"
    PASS=0
fi

if [[ "$(normalize_hex "${RAW_MIN:-}")" != "0X00000000" ]]; then
    echo "FAIL: DEBUGADDMIN 未成功清到 0x0000"
    PASS=0
fi

echo ""
for idx in "${!ADDRS[@]}"; do
    addr=${ADDRS[$idx]}
    expected=${PATTERNS[$idx]}
    actual=$(extract_last_read "$addr")
    [[ -n "$actual" ]] || actual="<unreadable>"
    echo "slot[$(printf '%02d' "$idx")] ${addr} -> ${actual} (expected ${expected})"
    if [[ "$(normalize_hex "$actual")" != "$(normalize_hex "$expected")" ]]; then
        PASS=0
        echo "FAIL: ${addr} 回读与期望不匹配"
    fi
done

echo ""
if [[ $PASS -eq 1 ]]; then
    echo "PASS: Phase 0C-B CEVA EM range sweep passed"
    exit 0
fi

echo "FAIL: Phase 0C-B CEVA EM range sweep failed"
exit 1