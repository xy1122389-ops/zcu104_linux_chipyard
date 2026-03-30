#!/usr/bin/env bash
set -euo pipefail
# Diagnostic: test if GDB can reliably write+readback 0x80000000
# Tests: restore, set {int}, monitor memU32

GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
HOST="$(ip route | awk '/default/ {print $3; exit}')"
PORT=2331
FW_BIN=/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin
FW_ELF=/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Extract just chunk_000 (first 1MB)
dd if="$FW_BIN" of="$TMPDIR/chunk_000.bin" bs=1048576 count=1 2>/dev/null
EXPECT=$(od -A n -t x4 -N 4 "$FW_BIN" | tr -d ' ')
echo "[info] Expected first word: 0x$EXPECT"

cat > "$TMPDIR/diag.gdb" <<EOF
set pagination off
set confirm off
set remotetimeout 60

target remote $HOST:$PORT
monitor reset
shell sleep 1
monitor halt

printf "\\n=== TEST 1: Direct read of current 0x80000000 value ===\\n"
printf "GDB x/ read: "
x/1wx 0x80000000
printf "\\n"

printf "=== TEST 2: Write known pattern via set {int} ===\\n"
set {int}0x80000000 = 0xdeadbeef
printf "Read back after set {int}: "
x/1wx 0x80000000
printf "\\n"

printf "=== TEST 3: Write another pattern via set {int} ===\\n"
set {int}0x80000000 = 0xcafebabe
printf "Read back: "
x/1wx 0x80000000
printf "\\n"

printf "=== TEST 4: Restore chunk_000.bin (1MB) to 0x80000000 ===\\n"
restore $TMPDIR/chunk_000.bin binary 0x80000000
printf "GDB x/ read after restore: "
x/1wx 0x80000000
printf "\\n"

printf "=== TEST 5: Flush and re-read ===\\n"
flushregs
printf "After flushregs x/ read: "
x/1wx 0x80000000
printf "\\n"

printf "=== TEST 6: Read via set variable (forced memory access) ===\\n"
set \$test_val = *(unsigned int *)0x80000000
printf "Via set variable: %x\\n", \$test_val
printf "\\n"

printf "=== TEST 7: Read addresses around 0x80000000 ===\\n"
printf "0x7FFFFFF0: "
x/4wx 0x7FFFFFF0
printf "0x80000000: "
x/4wx 0x80000000
printf "0x80000010: "
x/4wx 0x80000010
printf "0x80000020: "
x/4wx 0x80000020
printf "\\n"

printf "=== TEST 8: Without ELF symbol file read ===\\n"
printf "Symbol-free read via monitor ===\\n"
printf "Disasm from 0x80000000 (shows actual memory):\\n"
x/4i 0x80000000
printf "\\n"

printf "=== TEST 9: Verify chunk_000 byte 4-7 (offset 4) ===\\n"
printf "0x80000004: "
x/1wx 0x80000004
printf "\\n"

printf "=== DIAG COMPLETE ===\\n"
detach
quit
EOF

echo "Running diagnostic..."
echo "================================================================"
"$GDB" -batch -x "$TMPDIR/diag.gdb" 2>&1
echo "================================================================"
echo ""

echo "Now test WITHOUT ELF file (bare GDB):"
cat > "$TMPDIR/diag_noelf.gdb" <<EOF
set pagination off
set confirm off
set remotetimeout 60
set architecture riscv:rv64

target remote $HOST:$PORT
monitor halt

printf "\\n=== BARE GDB (no ELF): Read 0x80000000 ===\\n"
printf "0x80000000: "
x/4wx 0x80000000
printf "0x80000004: "
x/1wx 0x80000004
printf "0x80200000: "
x/1wx 0x80200000
printf "\\n=== DONE ===\\n"
detach
quit
EOF

echo "================================================================"
"$GDB" -batch -x "$TMPDIR/diag_noelf.gdb" 2>&1
echo "================================================================"
