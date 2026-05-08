#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
GDB=${GDB:-/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb}
JLINK_HOST=${JLINK_HOST:-127.0.0.1}
JLINK_PORT=${JLINK_PORT:-3333}

DEBUGADDMAX_ADDR=0x65000058
DEBUGADDMIN_ADDR=0x6500005c
EM_WINDOW_BASE=0x65010000
EM_WINDOW_LIMIT=0x6501ffff

BLOCK_IDS=(
    "low_block"
    "middle_block"
    "top_block"
)
BLOCK_LABELS=(
    "low block"
    "middle block"
    "top block"
)
BLOCK_BASES=(
    0x65010000
    0x65011000
    0x6501f000
)
BLOCK_SIZES=(
    256
    4096
    4096
)

PATTERN_NAMES=(
    "addr_xor"
    "addr_not_xor"
    "fixed_alternating"
)
PATTERN_DESCS=(
    "addr ^ 0xa5a50000"
    "~(addr ^ 0x5a5a0000)"
    "0x55aa33cc / 0xaa55cc33 alternating"
)

declare -A ACTUALS

hex32() {
    printf '0x%08X' "$(( ($1) & 0xffffffff ))"
}

normalize_hex() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

extract_last_read() {
    local addr=$1
    local addr_lc

    addr_lc=$(printf '%s' "$addr" | tr '[:upper:]' '[:lower:]')
    printf '%s\n' "$RESULT" | awk -v addr="$addr_lc" '{ token = tolower($1); if (token == addr ":") value=$2 } END { if (value != "") print value }'
}

expected_value() {
    local pattern_name=$1
    local addr=$2
    local word_index=$3
    local value

    case "$pattern_name" in
        addr_xor)
            value=$(( (addr ^ 0xa5a50000) & 0xffffffff ))
            ;;
        addr_not_xor)
            value=$(( (~(addr ^ 0x5a5a0000)) & 0xffffffff ))
            ;;
        fixed_alternating)
            if (( word_index % 2 == 0 )); then
                value=0x55aa33cc
            else
                value=0xaa55cc33
            fi
            ;;
        *)
            echo "ERROR: unknown pattern ${pattern_name}" >&2
            exit 1
            ;;
    esac

    hex32 "$value"
}

section_key() {
    local block_id=$1
    local pattern_name=$2

    printf '%s__%s' "$block_id" "$pattern_name"
}

ensure_jlink() {
    if ! nc -z -w 3 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
        echo "[info] J-Link GDB Server 未监听 ${JLINK_HOST}:${JLINK_PORT}，自动启动 Phase0b J-Link 流程..."
        bash "$SCRIPT_DIR/phase0b_start_jlink.sh"
    fi

    if ! nc -z -w 3 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
        echo "ERROR: J-Link GDB Server 仍未监听 ${JLINK_HOST}:${JLINK_PORT}"
        echo "       请先检查: bash scripts/phase0b_start_jlink.sh"
        exit 1
    fi
}

validate_blocks() {
    local block_base
    local block_size
    local last_addr
    local idx

    for idx in "${!BLOCK_LABELS[@]}"; do
        block_base=$(( ${BLOCK_BASES[$idx]} ))
        block_size=$(( ${BLOCK_SIZES[$idx]} ))
        last_addr=$(( block_base + block_size - 1 ))

        if (( (block_base & 0x3) != 0 )); then
            echo "ERROR: ${BLOCK_LABELS[$idx]} base 未按 32-bit 对齐: $(hex32 "$block_base")"
            exit 1
        fi

        if (( (block_size & 0x3) != 0 )); then
            echo "ERROR: ${BLOCK_LABELS[$idx]} size 不是 4-byte 整数倍: ${block_size}"
            exit 1
        fi

        if (( block_base < EM_WINDOW_BASE || last_addr > EM_WINDOW_LIMIT )); then
            echo "ERROR: ${BLOCK_LABELS[$idx]} 超出 EM window: $(hex32 "$block_base")..$(hex32 "$last_addr")"
            exit 1
        fi
    done
}

build_gdb_script() {
    local gdb_cmds=$1
    local block_idx
    local pattern_idx
    local block_base
    local block_size
    local block_id
    local pattern_name
    local word_count
    local section
    local offset
    local word_index
    local addr
    local expected

    {
        echo "set pagination off"
        echo "set remotetimeout 20"
        echo "target remote ${JLINK_HOST}:${JLINK_PORT}"
        echo "monitor halt"
        echo "monitor WriteU32 ${DEBUGADDMAX_ADDR} 0xffffffff"
        echo "monitor WriteU32 ${DEBUGADDMIN_ADDR} 0x00000000"
        echo "x/1wx ${DEBUGADDMAX_ADDR}"
        echo "x/1wx ${DEBUGADDMIN_ADDR}"
    } >"$gdb_cmds"

    for block_idx in "${!BLOCK_IDS[@]}"; do
        block_id=${BLOCK_IDS[$block_idx]}
        block_base=$(( ${BLOCK_BASES[$block_idx]} ))
        block_size=$(( ${BLOCK_SIZES[$block_idx]} ))
        word_count=$(( block_size / 4 ))

        for pattern_idx in "${!PATTERN_NAMES[@]}"; do
            pattern_name=${PATTERN_NAMES[$pattern_idx]}
            section=$(section_key "$block_id" "$pattern_name")
            echo "echo BEGIN|${section}\\n" >>"$gdb_cmds"

            for (( offset = 0, word_index = 0; offset < block_size; offset += 4, word_index++ )); do
                addr=$(( block_base + offset ))
                expected=$(expected_value "$pattern_name" "$addr" "$word_index")
                echo "monitor WriteU32 $(hex32 "$addr") $expected" >>"$gdb_cmds"
            done

            echo "x/${word_count}wx $(hex32 "$block_base")" >>"$gdb_cmds"
            echo "echo END|${section}\\n" >>"$gdb_cmds"
        done
    done

    {
        echo "monitor go"
        echo "detach"
    } >>"$gdb_cmds"
}

run_gdb_sweep() {
    local gdb_cmds

    gdb_cmds=$(mktemp)
    build_gdb_script "$gdb_cmds"

    if ! RESULT=$(timeout 1800 "$GDB" -q -batch -x "$gdb_cmds" 2>&1); then
        echo "$RESULT"
        rm -f "$gdb_cmds"
        echo "FAIL: GDB command failed during Phase 0D block sweep"
        exit 1
    fi

    rm -f "$gdb_cmds"
}

parse_result_reads() {
    local current_section=""
    local line
    local base_token
    local base
    local addr
    local addr_hex
    local idx
    local -a values

    ACTUALS=()

    while IFS= read -r line; do
        case "$line" in
            BEGIN\|*)
                current_section=${line#BEGIN|}
                continue
                ;;
            END\|*)
                current_section=""
                continue
                ;;
        esac

        if [[ -z "$current_section" ]]; then
            continue
        fi

        read -r base_token values[0] values[1] values[2] values[3] _ <<<"$line"
        if [[ ! "$base_token" =~ ^0[xX][0-9a-fA-F]+:$ ]]; then
            continue
        fi

        base=${base_token%:}
        for idx in "${!values[@]}"; do
            if [[ -z "${values[$idx]:-}" || ! "${values[$idx]}" =~ ^0[xX][0-9a-fA-F]+$ ]]; then
                continue
            fi

            addr=$(( base + (idx * 4) ))
            addr_hex=$(hex32 "$addr")
            ACTUALS["${current_section}|${addr_hex}"]=$(normalize_hex "${values[$idx]}")
        done
    done <<<"$RESULT"
}

verify_debug_window() {
    local actual

    actual=$(extract_last_read "$DEBUGADDMAX_ADDR")
    if [[ "$(normalize_hex "${actual:-}")" != "0XFFFFFFFF" ]]; then
        echo "FAIL: DEBUGADDMAX readback mismatch"
        echo "block: debug window"
        echo "address: ${DEBUGADDMAX_ADDR}"
        echo "expected: 0xFFFFFFFF"
        echo "actual: ${actual:-<unreadable>}"
        exit 1
    fi

    actual=$(extract_last_read "$DEBUGADDMIN_ADDR")
    if [[ "$(normalize_hex "${actual:-}")" != "0X00000000" ]]; then
        echo "FAIL: DEBUGADDMIN readback mismatch"
        echo "block: debug window"
        echo "address: ${DEBUGADDMIN_ADDR}"
        echo "expected: 0x00000000"
        echo "actual: ${actual:-<unreadable>}"
        exit 1
    fi
}

verify_results() {
    local block_idx
    local pattern_idx
    local block_id
    local block_label
    local block_base
    local block_size
    local pattern_name
    local pattern_desc
    local section
    local word_count
    local offset
    local word_index
    local addr
    local addr_hex
    local expected
    local actual

    verify_debug_window
    parse_result_reads

    for block_idx in "${!BLOCK_IDS[@]}"; do
        block_id=${BLOCK_IDS[$block_idx]}
        block_label=${BLOCK_LABELS[$block_idx]}
        block_base=$(( ${BLOCK_BASES[$block_idx]} ))
        block_size=$(( ${BLOCK_SIZES[$block_idx]} ))
        word_count=$(( block_size / 4 ))

        for pattern_idx in "${!PATTERN_NAMES[@]}"; do
            pattern_name=${PATTERN_NAMES[$pattern_idx]}
            pattern_desc=${PATTERN_DESCS[$pattern_idx]}
            section=$(section_key "$block_id" "$pattern_name")

            echo "[check] ${block_label} | pattern=${pattern_name} (${pattern_desc}) | words=${word_count}"

            for (( offset = 0, word_index = 0; offset < block_size; offset += 4, word_index++ )); do
                addr=$(( block_base + offset ))
                addr_hex=$(hex32 "$addr")
                expected=$(expected_value "$pattern_name" "$addr" "$word_index")
                actual=${ACTUALS["${section}|${addr_hex}"]:-}

                if [[ -z "$actual" ]]; then
                    echo "FAIL: unable to parse GDB readback"
                    echo "block: ${block_label}"
                    echo "pattern: ${pattern_name}"
                    echo "address: ${addr_hex}"
                    echo "expected: ${expected}"
                    echo "actual: <unreadable>"
                    exit 1
                fi

                if [[ "$actual" != "$(normalize_hex "$expected")" ]]; then
                    echo "FAIL: EM block sweep mismatch"
                    echo "block: ${block_label}"
                    echo "pattern: ${pattern_name}"
                    echo "address: ${addr_hex}"
                    echo "expected: ${expected}"
                    echo "actual: ${actual}"
                    exit 1
                fi
            done

            echo "PASS: ${block_label} ${pattern_name}"
            echo ""
        done

        echo "PASS: ${block_label} all patterns"
        echo ""
    done
}

main() {
    local idx
    local pattern_idx
    local block_base
    local block_size
    local block_end
    local total_words=0

    validate_blocks

    echo "=== Phase 0D CEVA EM block sweep ==="
    echo "J-Link      : ${JLINK_HOST}:${JLINK_PORT}"
    echo "EM window   : $(hex32 "$EM_WINDOW_BASE")..$(hex32 "$EM_WINDOW_LIMIT")"
    echo "DEBUGADDMAX : ${DEBUGADDMAX_ADDR} <- 0xffffffff"
    echo "DEBUGADDMIN : ${DEBUGADDMIN_ADDR} <- 0x00000000"
    echo ""
    echo "Blocks:"
    for idx in "${!BLOCK_LABELS[@]}"; do
        block_base=$(( ${BLOCK_BASES[$idx]} ))
        block_size=$(( ${BLOCK_SIZES[$idx]} ))
        block_end=$(( block_base + block_size - 1 ))
        total_words=$(( total_words + (block_size / 4) ))
        echo "- ${BLOCK_LABELS[$idx]}: $(hex32 "$block_base"), size=${block_size}B, end=$(hex32 "$block_end")"
    done
    echo ""
    echo "Patterns:"
    for pattern_idx in "${!PATTERN_NAMES[@]}"; do
        echo "- ${PATTERN_NAMES[$pattern_idx]}: ${PATTERN_DESCS[$pattern_idx]}"
    done
    echo ""
    echo "[plan] single GDB session, total words per pattern set=${total_words}"
    echo ""

    ensure_jlink
    run_gdb_sweep
    verify_results
    echo "PASS: Phase 0D EM block sweep passed"
}

main "$@"