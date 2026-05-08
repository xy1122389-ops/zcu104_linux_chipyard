#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
JLINK_HOST=127.0.0.1
JLINK_PORT=3333

# CEVA DEBUGADDMAX / DEBUGADDMIN are DM registers 0x16 / 0x17.
# They control the local 16-bit EM debug range checked by rw_dm_em_cntl.
DEBUGADDMAX_ADDR=0x65000058
DEBUGADDMIN_ADDR=0x6500005c

# AHB bit 16 selects the EM path, so the system EM debug window is:
#   0x65010000 .. 0x6501ffff
EM_WORD0_ADDR=${EM_WORD0_ADDR:-0x65010000}
EM_WORD1_ADDR=${EM_WORD1_ADDR:-0x65010004}
PATTERN0=${PATTERN0:-0xA5C00C0A}
PATTERN1=${PATTERN1:-0x5A3F3CF5}

echo "=== Phase 0C-A CEVA EM window read/write smoke ==="
echo "J-Link: ${JLINK_HOST}:${JLINK_PORT}"
echo "DEBUGADDMAX: ${DEBUGADDMAX_ADDR} <- 0xffffffff"
echo "DEBUGADDMIN: ${DEBUGADDMIN_ADDR} <- 0x00000000"
echo "EM word0    : ${EM_WORD0_ADDR} <- ${PATTERN0}"
echo "EM word1    : ${EM_WORD1_ADDR} <- ${PATTERN1}"
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

RESULT=$(timeout 60 "$GDB" -q -batch \
    -ex "set remotetimeout 20" \
    -ex "target remote ${JLINK_HOST}:${JLINK_PORT}" \
    -ex "monitor halt" \
    -ex "monitor WriteU32 ${DEBUGADDMAX_ADDR} 0xffffffff" \
    -ex "monitor WriteU32 ${DEBUGADDMIN_ADDR} 0x00000000" \
    -ex "x/1wx ${DEBUGADDMAX_ADDR}" \
    -ex "x/1wx ${DEBUGADDMIN_ADDR}" \
    -ex "x/1wx ${EM_WORD0_ADDR}" \
    -ex "monitor WriteU32 ${EM_WORD0_ADDR} ${PATTERN0}" \
    -ex "x/1wx ${EM_WORD0_ADDR}" \
    -ex "x/1wx ${EM_WORD1_ADDR}" \
    -ex "monitor WriteU32 ${EM_WORD1_ADDR} ${PATTERN1}" \
    -ex "x/1wx ${EM_WORD0_ADDR}" \
    -ex "x/1wx ${EM_WORD1_ADDR}" \
    -ex "monitor go" \
    -ex "detach" \
    2>&1)

echo "$RESULT"
echo ""

extract_last_read() {
    local addr=$1
    printf '%s\n' "$RESULT" | awk -v addr="$addr" '$1 == addr":" { value=$2 } END { if (value != "") print value }'
}

normalize_hex() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

RAW_MAX=$(extract_last_read "$DEBUGADDMAX_ADDR")
RAW_MIN=$(extract_last_read "$DEBUGADDMIN_ADDR")
RAW0=$(extract_last_read "$EM_WORD0_ADDR")
RAW1=$(extract_last_read "$EM_WORD1_ADDR")

[[ -n "$RAW_MAX" ]] || RAW_MAX="<unreadable>"
[[ -n "$RAW_MIN" ]] || RAW_MIN="<unreadable>"
[[ -n "$RAW0" ]] || RAW0="<unreadable>"
[[ -n "$RAW1" ]] || RAW1="<unreadable>"

echo "DEBUGADDMAX readback: ${RAW_MAX}"
echo "DEBUGADDMIN readback: ${RAW_MIN}"
echo "EM word0 readback   : ${RAW0}"
echo "EM word1 readback   : ${RAW1}"
echo ""

PASS=1

if [[ "$(normalize_hex "$RAW_MAX")" != "0XFFFFFFFF" ]]; then
    echo "FAIL: DEBUGADDMAX 未成功打开到 0xffff"
    PASS=0
fi

if [[ "$(normalize_hex "$RAW_MIN")" != "0X00000000" ]]; then
    echo "FAIL: DEBUGADDMIN 未成功清到 0x0000"
    PASS=0
fi

if [[ "$(normalize_hex "$RAW0")" != "$(normalize_hex "$PATTERN0")" ]]; then
    echo "FAIL: EM word0 读写不匹配"
    PASS=0
fi

if [[ "$(normalize_hex "$RAW1")" != "$(normalize_hex "$PATTERN1")" ]]; then
    echo "FAIL: EM word1 读写不匹配"
    PASS=0
fi

if [[ $PASS -eq 1 ]]; then
    echo "PASS: Phase 0C-A CEVA EM window read/write smoke passed"
    exit 0
fi

echo "FAIL: Phase 0C-A CEVA EM window read/write smoke failed"
exit 1