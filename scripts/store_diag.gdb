# store_diag.gdb — Bare-metal store pattern test on Rocket core
# Runs BEFORE kernel boot to test for 2-byte store duplication bug
# Usage: riscv64-unknown-elf-gdb -batch -x store_diag.gdb

# This test:
# 1. Writes known patterns using different store widths to DDR
# 2. Reads back via GDB memory read (which uses SBA, bypassing cache)
# 3. Checks for duplication

set pagination off
set confirm off
set remotetimeout 120

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import gdb, time
host = "172.19.128.1"
port = 12331
for attempt in range(1, 4):
    try:
        gdb.execute(f"target remote {host}:{port}")
        gdb.write(f"[info] Connected on attempt {attempt}\n")
        break
    except gdb.error as err:
        gdb.write(f"[warn] attempt {attempt} failed: {err}\n")
        if attempt < 3:
            time.sleep(2)
        else:
            raise
end

monitor halt

python
import gdb, struct, time

gdb.write("\n=== Store Pattern Diagnostic ===\n")

# Use 0x8F000000 (within DDR range, 240MB above base, well past kernel)
SCRATCH = 0x8F000000

# First, write a known pattern via SBA (GDB restore) to init the area
# Then have the CPU execute stores and compare

# Step 1: Zero scratch area via SBA
gdb.write("[diag] Zeroing scratch area via SBA...\n")
for off in range(0, 256, 8):
    gdb.execute(f"set {{long}}0x{SCRATCH+off:x} = 0")
# fence
gdb.execute("set $pc = 0x80036200")
gdb.execute("set {int}0x80036200 = 0x0000100f")  # fence.i
gdb.execute("set {int}0x80036204 = 0x00100073")  # ebreak
gdb.execute("si")  # execute fence.i

# Step 2: Assemble store test routine
# The test routine writes various patterns to SCRATCH area:
#
# Test A: 8 x sd (doubleword stores) at sequential addresses
# Test B: 16 x sw (word stores) 
# Test C: 32 x sh (halfword stores)
# Test D: 64 x sb (byte stores)
# Then fence + ebreak
#
# Pattern: each store writes a unique value so we can verify

CODE_BASE = 0x80036200
code = []

# Helper: assemble a simple sequence
# We'll use a0 as base address, a1 as data register
# Strategy: use LUI+ADDI to set registers, then store

# Set a0 = SCRATCH base
scratch_hi = (SCRATCH >> 12) & 0xFFFFF
scratch_lo = SCRATCH & 0xFFF
if scratch_lo >= 0x800:
    scratch_hi += 1
    scratch_lo -= 0x1000  # signed
    scratch_lo &= 0xFFF

# Use a simpler approach: GDB set registers, then execute instructions
gdb.execute(f"set $a0 = 0x{SCRATCH:x}")
gdb.execute(f"set $a1 = 0xDEADBEEFCAFEBABE")

# Test A: doubleword stores
gdb.write("[diag] Test A: 8 x sd (doubleword)...\n")
base = SCRATCH
for i in range(8):
    val = 0x1111111111111111 * (i + 1)
    addr = base + i * 8
    gdb.execute(f"set $a1 = 0x{val:016x}")
    gdb.execute(f"set $a0 = 0x{addr:x}")
    # Encode: sd a1, 0(a0) = 0x00b53023
    gdb.execute(f"set {{int}}0x{CODE_BASE:x} = 0x00b53023")    # sd a1, 0(a0)
    gdb.execute(f"set {{int}}0x{CODE_BASE+4:x} = 0x00100073")  # ebreak
    gdb.execute(f"set $pc = 0x{CODE_BASE:x}")
    gdb.execute("si")  # sd
    gdb.execute("si")  # ebreak

# Fence
gdb.execute(f"set {{int}}0x{CODE_BASE:x} = 0x0ff0000f")     # fence iorw,iorw
gdb.execute(f"set {{int}}0x{CODE_BASE+4:x} = 0x0000100f")    # fence.i
gdb.execute(f"set {{int}}0x{CODE_BASE+8:x} = 0x00100073")    # ebreak
gdb.execute(f"set $pc = 0x{CODE_BASE:x}")
gdb.execute("si")  # fence
gdb.execute("si")  # fence.i
gdb.execute("si")  # ebreak

# Read back Test A and verify
gdb.write("[diag] Verifying Test A...\n")
errors_a = 0
for i in range(8):
    val = 0x1111111111111111 * (i + 1)
    addr = base + i * 8
    readback = int(gdb.parse_and_eval(f"*(unsigned long long*)0x{addr:x}"))
    if readback != val:
        gdb.write(f"  [FAIL] sd: addr=0x{addr:x} expected=0x{val:016x} got=0x{readback:016x}\n")
        errors_a += 1
if errors_a == 0:
    gdb.write("  [PASS] All 8 sd stores verified\n")

# Check for duplication: read the 8 bytes AFTER the last store
last_addr = base + 8 * 8  # should be all zeros
readback = int(gdb.parse_and_eval(f"*(unsigned long long*)0x{last_addr:x}"))
if readback != 0:
    gdb.write(f"  [DUP?] Bytes after last sd: 0x{readback:016x} (expected 0)\n")
else:
    gdb.write(f"  [OK] No duplication after last sd\n")

# Test B: halfword stores with specific alignment  
gdb.write("\n[diag] Test B: 32 x sh (halfword) at various offsets...\n")
base_b = SCRATCH + 256
errors_b = 0

for i in range(32):
    val = 0x1000 + i
    addr = base_b + i * 2
    gdb.execute(f"set $a1 = 0x{val:x}")
    gdb.execute(f"set $a0 = 0x{addr:x}")
    # sh a1, 0(a0) = 0x00b51023
    gdb.execute(f"set {{int}}0x{CODE_BASE:x} = 0x00b51023")    # sh a1, 0(a0)
    gdb.execute(f"set {{int}}0x{CODE_BASE+4:x} = 0x00100073")  # ebreak
    gdb.execute(f"set $pc = 0x{CODE_BASE:x}")
    gdb.execute("si")  # sh
    gdb.execute("si")  # ebreak

# Fence
gdb.execute(f"set {{int}}0x{CODE_BASE:x} = 0x0ff0000f")
gdb.execute(f"set {{int}}0x{CODE_BASE+4:x} = 0x0000100f")
gdb.execute(f"set {{int}}0x{CODE_BASE+8:x} = 0x00100073")
gdb.execute(f"set $pc = 0x{CODE_BASE:x}")
gdb.execute("si")
gdb.execute("si")
gdb.execute("si")

# Read back Test B
gdb.write("[diag] Verifying Test B...\n")
for i in range(32):
    val = 0x1000 + i
    addr = base_b + i * 2
    readback = int(gdb.parse_and_eval(f"*(unsigned short*)0x{addr:x}"))
    if readback != val:
        gdb.write(f"  [FAIL] sh: addr=0x{addr:x} expected=0x{val:04x} got=0x{readback:04x}\n")
        errors_b += 1
if errors_b == 0:
    gdb.write("  [PASS] All 32 sh stores verified\n")

# Check duplication after halfword region
last_hw = base_b + 64  # first byte after the 32 halfwords
readback = int(gdb.parse_and_eval(f"*(unsigned long long*)0x{last_hw:x}"))
if readback != 0:
    gdb.write(f"  [DUP?] After halfword region: 0x{readback:016x}\n")
else:
    gdb.write(f"  [OK] No duplication after halfword region\n")

# Test C: memcpy-like pattern (consecutive sd stores simulating string copy)
gdb.write("\n[diag] Test C: consecutive sd stores (memcpy pattern)...\n")
base_c = SCRATCH + 512
# Write a pattern like "Hello, World! This is a test.\n\0..."
# Using sd stores every 8 bytes
test_pattern = b"Hello, World! This is a test string for diagnosing.\n\x00\x00\x00\x00\x00"
# Pad to 64 bytes
test_pattern = test_pattern.ljust(64, b'\x00')

for i in range(0, 64, 8):
    val = int.from_bytes(test_pattern[i:i+8], 'little')
    addr = base_c + i
    gdb.execute(f"set $a1 = 0x{val:016x}")
    gdb.execute(f"set $a0 = 0x{addr:x}")
    gdb.execute(f"set {{int}}0x{CODE_BASE:x} = 0x00b53023")
    gdb.execute(f"set {{int}}0x{CODE_BASE+4:x} = 0x00100073")
    gdb.execute(f"set $pc = 0x{CODE_BASE:x}")
    gdb.execute("si")
    gdb.execute("si")

# Fence
gdb.execute(f"set {{int}}0x{CODE_BASE:x} = 0x0ff0000f")
gdb.execute(f"set {{int}}0x{CODE_BASE+4:x} = 0x0000100f")
gdb.execute(f"set {{int}}0x{CODE_BASE+8:x} = 0x00100073")
gdb.execute(f"set $pc = 0x{CODE_BASE:x}")
gdb.execute("si")
gdb.execute("si")
gdb.execute("si")

# Read back
gdb.write("[diag] Verifying Test C...\n")
readback_c = gdb.selected_inferior().read_memory(base_c, 80)  # extra 16 bytes to check duplication
readback_bytes = bytes(readback_c)
expected = test_pattern[:64]
match = readback_bytes[:64] == expected
gdb.write(f"  Data match: {'PASS' if match else 'FAIL'}\n")
if not match:
    for i in range(64):
        if readback_bytes[i] != expected[i]:
            gdb.write(f"  First mismatch at byte {i}: expected 0x{expected[i]:02x} got 0x{readback_bytes[i]:02x}\n")
            break

overflow = readback_bytes[64:80]
if any(b != 0 for b in overflow):
    gdb.write(f"  [DUP?] Overflow bytes (64-79): {overflow.hex()}\n")
    gdb.write(f"  [DUP?] ASCII: {overflow}\n")
else:
    gdb.write(f"  [OK] No overflow/duplication after test pattern\n")

gdb.write("\n=== Store Diagnostic Complete ===\n")
gdb.write(f"NOTE: This test runs in M-mode (no MMU). The 2-byte bug may only\n")
gdb.write(f"manifest with Sv39 enabled. Consider repeating after MMU setup.\n")
end
