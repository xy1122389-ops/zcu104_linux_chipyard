set pagination off
set confirm off
set remotetimeout 600

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import gdb, os, time
host = os.environ.get("JLINK_HOST", "172.19.128.1")
port = int(os.environ.get("JLINK_PORT", "2331"))
gdb.write(f"[info] Connecting to J-Link at {host}:{port}\n")
for attempt in range(1, 4):
    try:
        gdb.execute(f"target remote {host}:{port}")
        gdb.write(f"[info] Connected on attempt {attempt}\n")
        break
    except gdb.error as err:
        if attempt == 3:
            raise
        time.sleep(2)
end

monitor halt
monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

echo \n=== Bare-metal store/load test for byte doubling ===\n
python
import gdb, time, struct

# Test area: 0x80F00000 (scratch memory, not in payload)
TEST_BASE = 0x80F00000
CODE_BASE = 0x80F10000

# --- Test 1: Basic store/load via CPU ---
# Write a known pattern via CPU and read it back via CPU
# This tests if the CPU's own stores have the doubling issue

# Program: write test patterns, then ebreak
# Registers: a0 = dest base, a1 = test word count
# Strategy:
#   Store the string "Hello_World!\0" (13 bytes) at a0 using sb (byte stores)
#   Then store via sh (halfword)
#   Then store via sw (word)
#   Then store via sd (doubleword)
#   Then ebreak

test_string = b"Hello_World!\x00"

# Write test code at CODE_BASE
code = []
# fence.i first (since we write code via SBA)
code.append(0x0000100f)  # fence.i

# --- Byte store test ---
# Store "Hello_World!\0" byte by byte at a0
for i, b in enumerate(test_string):
    # li t0, byte_value
    code.append(0x00000293 | (b << 20))  # addi t0, zero, byte_value
    # sb t0, offset(a0)
    imm_hi = (i >> 5) & 0x7F
    imm_lo = i & 0x1F
    code.append(0x00050023 | (imm_hi << 25) | (0x5 << 20) | (imm_lo << 7))  # sb t0, i(a0)

# --- Halfword store test ---
# Store 0xCAFE at a0+64 via sh
code.append(0x0000E293 | (0xFFFFCAFE & 0xFFF) << 20)  # WRONG - let me use lui+addi
# Actually, for simplicity, just use two byte stores to write 0xFE 0xCA
code.pop()  # remove the bad one
# Store 0xFE at a0+64
code.append(0x0FE00293)  # li t0, 0xFE  -- WRONG, 0xFE > 127 signed
# Actually, addi sign-extends. 0xFE = -2 in signed byte context
# Let's use: li t0, 0xFE → addi t0, x0, -2 → 0xFFE00293
code.pop()
code.append(0xFFE00293)  # addi t0, zero, -2 → t0 = 0xFFFFFFFFFFFFFFFF - 1 = -2 = 0x...FE
# sb t0, 64(a0)
code.append(0x04550023)  # sb t0, 64(a0)  -- hmm, imm encoding

# This is getting complicated with manual encoding. Let me use a simpler approach.
# Just write pattern via SBA, then have CPU read+write it, then verify via SBA read.

gdb.write("[test] Using simpler approach: SBA write -> CPU readback -> verify\n")

# Clear test area
for i in range(0, 128, 4):
    gdb.execute(f"set *(unsigned int*)0x{TEST_BASE + i:x} = 0")

# Write known pattern via SBA
test_data = b"The quick brown fox jumps over the lazy dog. 0123456789ABCDEF!@#$%^&*()_+" + bytes(range(64))
for i in range(0, len(test_data), 4):
    chunk = test_data[i:i+4]
    if len(chunk) < 4:
        chunk = chunk + b'\x00' * (4 - len(chunk))
    val = struct.unpack('<I', chunk)[0]
    gdb.execute(f"set *(unsigned int*)0x{TEST_BASE + i:x} = 0x{val:08x}")

gdb.write(f"[test] Wrote {len(test_data)} bytes at 0x{TEST_BASE:08x} via SBA\n")

# Copyback the test data (make dirty in L2)
# Write copyback routine
COPYBACK_ADDR = CODE_BASE
instrs = [
    0x0000100f,  # fence.i
    0x00053283,  # ld t0, 0(a0)
    0x00553023,  # sd t0, 0(a0)
    0x04050513,  # addi a0, a0, 64
    0xFEB54AE3,  # blt a0, a1, -12
    0x00100073,  # ebreak
]
for j, val in enumerate(instrs):
    gdb.execute(f"set *(unsigned int*)0x{COPYBACK_ADDR + j*4:x} = 0x{val:08x}")

# Copyback test data
gdb.execute(f"set $a0 = 0x{TEST_BASE:x}")
gdb.execute(f"set $a1 = 0x{TEST_BASE + ((len(test_data) + 63) & ~63):x}")
gdb.execute(f"set $pc = 0x{COPYBACK_ADDR:x}")
gdb.execute(f"hbreak *0x{COPYBACK_ADDR + 20:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.write("[test] Test data copyback done\n")

# Now read back via SBA (GDB read) and compare
readback = bytearray()
for i in range(0, len(test_data), 4):
    val = int(gdb.parse_and_eval(f"*(unsigned int*)0x{TEST_BASE + i:x}"))
    readback.extend(struct.pack('<I', val & 0xFFFFFFFF))
readback = readback[:len(test_data)]

mismatches = 0
for i in range(len(test_data)):
    if test_data[i] != readback[i]:
        gdb.write(f"[MISMATCH] offset {i}: expected 0x{test_data[i]:02x} got 0x{readback[i]:02x}\n")
        mismatches += 1
        if mismatches > 20:
            break

if mismatches == 0:
    gdb.write("[PASS] SBA write + copyback + SBA read: all bytes match\n")
else:
    gdb.write(f"[FAIL] {mismatches} mismatches found\n")

# --- Test 2: CPU memcpy test ---
# Write code that copies data from TEST_BASE to TEST_BASE+0x200 using ld+sd
# Then we read TEST_BASE+0x200 via SBA to check for doubling

gdb.write("\n[test2] CPU ld+sd copy test (simulates memcpy)...\n")
SRC = TEST_BASE
DST = TEST_BASE + 0x200
COPY_LEN = len(test_data)

# Clear destination
for i in range(0, COPY_LEN + 64, 4):
    gdb.execute(f"set *(unsigned int*)0x{DST + i:x} = 0")

# Write copy code: load 8 bytes from src, store to dst, advance, loop
# a0 = src, a1 = dst, a2 = src_end
COPY_CODE = COPYBACK_ADDR + 0x100
copy_instrs = [
    0x0000100f,  # fence.i
    0x00053283,  # ld t0, 0(a0)
    0x00553023 | (0x58 << 15),  # sd t0, 0(a1) -- actually need correct encoding
]
# Let me just encode this properly
# The copy loop: ld t0, 0(a0); sd t0, 0(a1); addi a0,a0,8; addi a1,a1,8; blt a0,a2,-12
copy_instrs = [
    0x0000100f,  # fence.i
    0x00053283,  # ld t0, 0(a0)   -- rs1=a0=x10
    0x0055b023,  # sd t0, 0(a1)   -- rs1=a1=x11, rs2=t0=x5
    0x00850513,  # addi a0, a0, 8
    0x00858593,  # addi a1, a1, 8
    0xFEC54AE3,  # blt a0, a2, -12  -- branch to ld
    0x00100073,  # ebreak
]
for j, val in enumerate(copy_instrs):
    gdb.execute(f"set *(unsigned int*)0x{COPY_CODE + j*4:x} = 0x{val:08x}")

# Run the copy
copy_len_aligned = (COPY_LEN + 7) & ~7
gdb.execute(f"set $a0 = 0x{SRC:x}")
gdb.execute(f"set $a1 = 0x{DST:x}")
gdb.execute(f"set $a2 = 0x{SRC + copy_len_aligned:x}")
gdb.execute(f"set $pc = 0x{COPY_CODE:x}")
gdb.execute(f"hbreak *0x{COPY_CODE + 24:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")

# Read destination via SBA and compare with source
dst_data = bytearray()
for i in range(0, copy_len_aligned, 4):
    val = int(gdb.parse_and_eval(f"*(unsigned int*)0x{DST + i:x}"))
    dst_data.extend(struct.pack('<I', val & 0xFFFFFFFF))
dst_data = dst_data[:len(test_data)]

mismatches2 = 0
for i in range(len(test_data)):
    if test_data[i] != dst_data[i]:
        gdb.write(f"[MISMATCH] offset {i}: expected 0x{test_data[i]:02x} got 0x{dst_data[i]:02x}\n")
        mismatches2 += 1
        if mismatches2 > 20:
            break

if mismatches2 == 0:
    gdb.write("[PASS] CPU ld+sd copy: all bytes match\n")
else:
    gdb.write(f"[FAIL] {mismatches2} mismatches in CPU copy\n")

# --- Test 3: CPU sb (byte store) test ---
gdb.write("\n[test3] CPU byte-store (sb) test...\n")
DST3 = TEST_BASE + 0x400

# Code: load each byte from src via lbu, store to dst via sb
SB_CODE = COPYBACK_ADDR + 0x200
sb_instrs = [
    0x0000100f,  # fence.i
    0x00054283,  # lbu t0, 0(a0)
    0x0055c023,  # sb t0, 0(a1) -- err, need correct encoding
]
# sb t0, 0(a1): opcode=0x23, funct3=0b000, rs1=a1=x11, rs2=t0=x5
# sb rs2, imm(rs1) = imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode
# imm=0: 0000000 | 00101 | 01011 | 000 | 00000 | 0100011
# = 0x00558023
sb_instrs = [
    0x0000100f,  # fence.i
    0x00054283,  # lbu t0, 0(a0)
    0x00558023,  # sb t0, 0(a1)
    0x00150513,  # addi a0, a0, 1
    0x00158593,  # addi a1, a1, 1
    0xFEC54AE3,  # blt a0, a2, -12
    0x00100073,  # ebreak
]
for j, val in enumerate(sb_instrs):
    gdb.execute(f"set *(unsigned int*)0x{SB_CODE + j*4:x} = 0x{val:08x}")

# Clear destination
for i in range(0, COPY_LEN + 8, 4):
    gdb.execute(f"set *(unsigned int*)0x{DST3 + i:x} = 0")

# Run byte copy
gdb.execute(f"set $a0 = 0x{SRC:x}")
gdb.execute(f"set $a1 = 0x{DST3:x}")
gdb.execute(f"set $a2 = 0x{SRC + len(test_data):x}")
gdb.execute(f"set $pc = 0x{SB_CODE:x}")
gdb.execute(f"hbreak *0x{SB_CODE + 24:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")

# Verify
dst3_data = bytearray()
for i in range(0, len(test_data) + 4, 4):
    val = int(gdb.parse_and_eval(f"*(unsigned int*)0x{DST3 + i:x}"))
    dst3_data.extend(struct.pack('<I', val & 0xFFFFFFFF))
dst3_data = dst3_data[:len(test_data)]

mismatches3 = 0
for i in range(len(test_data)):
    if test_data[i] != dst3_data[i]:
        gdb.write(f"[MISMATCH] offset {i}: expected 0x{test_data[i]:02x} got 0x{dst3_data[i]:02x}\n")
        mismatches3 += 1
        if mismatches3 > 20:
            break

if mismatches3 == 0:
    gdb.write("[PASS] CPU sb copy: all bytes match\n")
else:
    gdb.write(f"[FAIL] {mismatches3} mismatches in CPU sb copy\n")

gdb.write("\n=== All tests complete ===\n")
end

quit
