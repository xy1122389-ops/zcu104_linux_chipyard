set pagination off
set confirm off
set remotetimeout 600

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import gdb, os, time
host = os.environ.get("JLINK_HOST", "172.19.128.1")
port = int(os.environ.get("JLINK_PORT", "2331"))
for attempt in range(1, 4):
    try:
        gdb.execute(f"target remote {host}:{port}")
        gdb.write(f"[info] Connected on attempt {attempt}\n")
        break
    except gdb.error as err:
        if attempt == 3: raise
        time.sleep(2)
end

monitor halt
monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

python
import gdb, struct

TEST_BASE = 0x80F00000
CODE_BASE = 0x80F10000

# Known test pattern
test_data = b"The quick brown fox jumps over the lazy dog. 0123456789ABCDEF!@#$%^&*()_+" + bytes(range(64))
test_len = len(test_data)

# Write test pattern to TEST_BASE via SBA
for i in range(0, test_len + 4, 4):
    chunk = test_data[i:i+4] if i < test_len else b'\x00\x00\x00\x00'
    if len(chunk) < 4:
        chunk = chunk + b'\x00' * (4 - len(chunk))
    val = struct.unpack('<I', chunk)[0]
    gdb.execute(f"set *(unsigned int*)0x{TEST_BASE + i:x} = 0x{val:08x}")

# Write copyback routine at CODE_BASE (to dirty SBA data)
cb_instrs = [
    0x0000100f,  # fence.i
    0x00053283,  # ld t0, 0(a0)
    0x00553023,  # sd t0, 0(a0)
    0x04050513,  # addi a0, a0, 64
    0xFEB54AE3,  # blt a0, a1, -12
    0x00100073,  # ebreak
]
for j, val in enumerate(cb_instrs):
    gdb.execute(f"set *(unsigned int*)0x{CODE_BASE + j*4:x} = 0x{val:08x}")

# Copyback test data + code
for region in [(TEST_BASE, TEST_BASE + 256), (CODE_BASE, CODE_BASE + 64)]:
    gdb.execute(f"set $a0 = 0x{region[0]:x}")
    gdb.execute(f"set $a1 = 0x{region[1]:x}")
    gdb.execute(f"set $pc = 0x{CODE_BASE:x}")
    gdb.execute(f"hbreak *0x{CODE_BASE + 20:x}")
    gdb.execute("continue")
    gdb.execute("delete breakpoints")
gdb.write(f"[setup] Test data ({test_len} bytes) and code ready\n")

# === Test 1: SBA write + copyback + SBA read ===
gdb.write("\n=== Test 1: SBA write -> copyback -> SBA readback ===\n")
readback = bytearray()
for i in range(0, test_len, 4):
    val = int(gdb.parse_and_eval(f"*(unsigned int*)0x{TEST_BASE + i:x}"))
    readback.extend(struct.pack('<I', val & 0xFFFFFFFF))
readback = readback[:test_len]
mm = sum(1 for i in range(test_len) if test_data[i] != readback[i])
gdb.write(f"[Test1] {'PASS' if mm == 0 else 'FAIL'}: {mm} mismatches\n")

# === Test 2: CPU ld+sd copy ===
# Code: ld t0,0(a0); sd t0,0(a1); addi a0,8; addi a1,8; blt a0,a2,loop; ebreak
gdb.write("\n=== Test 2: CPU ld+sd copy ===\n")
DST2 = TEST_BASE + 0x200
# Clear destination
for i in range(0, test_len + 64, 4):
    gdb.execute(f"set *(unsigned int*)0x{DST2 + i:x} = 0")
# Copyback the cleared destination
gdb.execute(f"set $a0 = 0x{DST2:x}")
gdb.execute(f"set $a1 = 0x{DST2 + 256:x}")
gdb.execute(f"set $pc = 0x{CODE_BASE + 4:x}")
gdb.execute(f"hbreak *0x{CODE_BASE + 20:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")

# Write ld+sd copy loop at CODE_BASE+0x100
COPY_LD = CODE_BASE + 0x100
# CORRECT encodings from assembler:
# ld t0, 0(a0)     = 0x00053283
# sd t0, 0(a1)     = 0x0055b023
# addi a0, a0, 8   = 0x00850513
# addi a1, a1, 8   = 0x00858593
# blt a0, a2, -16  = 0xfec548e3
# ebreak           = 0x00100073
ld_sd_instrs = [
    0x0000100f,  # fence.i
    0x00053283,  # ld t0, 0(a0)
    0x0055b023,  # sd t0, 0(a1)
    0x00850513,  # addi a0, a0, 8
    0x00858593,  # addi a1, a1, 8
    0xfec548e3,  # blt a0, a2, -16  (back to ld)
    0x00100073,  # ebreak
]
for j, val in enumerate(ld_sd_instrs):
    gdb.execute(f"set *(unsigned int*)0x{COPY_LD + j*4:x} = 0x{val:08x}")
# Copyback the code
gdb.execute(f"set $a0 = 0x{COPY_LD:x}")
gdb.execute(f"set $a1 = 0x{COPY_LD + 64:x}")
gdb.execute(f"set $pc = 0x{CODE_BASE:x}")
gdb.execute(f"hbreak *0x{CODE_BASE + 20:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")

# Run the ld+sd copy
copy_len_aligned = (test_len + 7) & ~7
gdb.execute(f"set $a0 = 0x{TEST_BASE:x}")
gdb.execute(f"set $a1 = 0x{DST2:x}")
gdb.execute(f"set $a2 = 0x{TEST_BASE + copy_len_aligned:x}")
gdb.execute(f"set $pc = 0x{COPY_LD:x}")
gdb.execute(f"hbreak *0x{COPY_LD + 24:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")

# Verify destination via SBA read
dst2 = bytearray()
for i in range(0, copy_len_aligned, 4):
    val = int(gdb.parse_and_eval(f"*(unsigned int*)0x{DST2 + i:x}"))
    dst2.extend(struct.pack('<I', val & 0xFFFFFFFF))
dst2 = dst2[:test_len]
mm2 = 0
for i in range(test_len):
    if test_data[i] != dst2[i]:
        if mm2 < 10:
            gdb.write(f"  [DIFF] off={i}: exp=0x{test_data[i]:02x}('{chr(test_data[i]) if 32<=test_data[i]<=126 else '?'}') got=0x{dst2[i]:02x}('{chr(dst2[i]) if 32<=dst2[i]<=126 else '?'}')\n")
        mm2 += 1
gdb.write(f"[Test2] {'PASS' if mm2 == 0 else 'FAIL'}: {mm2} mismatches out of {test_len} bytes\n")

# === Test 3: CPU lbu+sb copy ===
gdb.write("\n=== Test 3: CPU lbu+sb byte copy ===\n")
DST3 = TEST_BASE + 0x400
for i in range(0, test_len + 64, 4):
    gdb.execute(f"set *(unsigned int*)0x{DST3 + i:x} = 0")
# Copyback cleared dest
gdb.execute(f"set $a0 = 0x{DST3:x}")
gdb.execute(f"set $a1 = 0x{DST3 + 256:x}")
gdb.execute(f"set $pc = 0x{CODE_BASE + 4:x}")
gdb.execute(f"hbreak *0x{CODE_BASE + 20:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")

# Write lbu+sb loop
COPY_SB = CODE_BASE + 0x200
# lbu t0, 0(a0)     = 0x00054283
# sb t0, 0(a1)      = 0x00558023
# addi a0, a0, 1    = 0x00150513
# addi a1, a1, 1    = 0x00158593
# blt a0, a2, -16   = 0xfec548e3
# ebreak            = 0x00100073
sb_instrs = [
    0x0000100f,  # fence.i
    0x00054283,  # lbu t0, 0(a0)
    0x00558023,  # sb t0, 0(a1)
    0x00150513,  # addi a0, a0, 1
    0x00158593,  # addi a1, a1, 1
    0xfec548e3,  # blt a0, a2, -16  (back to lbu)
    0x00100073,  # ebreak
]
for j, val in enumerate(sb_instrs):
    gdb.execute(f"set *(unsigned int*)0x{COPY_SB + j*4:x} = 0x{val:08x}")
# Copyback code
gdb.execute(f"set $a0 = 0x{COPY_SB:x}")
gdb.execute(f"set $a1 = 0x{COPY_SB + 64:x}")
gdb.execute(f"set $pc = 0x{CODE_BASE:x}")
gdb.execute(f"hbreak *0x{CODE_BASE + 20:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")

# Run lbu+sb copy
gdb.execute(f"set $a0 = 0x{TEST_BASE:x}")
gdb.execute(f"set $a1 = 0x{DST3:x}")
gdb.execute(f"set $a2 = 0x{TEST_BASE + test_len:x}")
gdb.execute(f"set $pc = 0x{COPY_SB:x}")
gdb.execute(f"hbreak *0x{COPY_SB + 24:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")

# Verify
dst3 = bytearray()
for i in range(0, test_len + 4, 4):
    val = int(gdb.parse_and_eval(f"*(unsigned int*)0x{DST3 + i:x}"))
    dst3.extend(struct.pack('<I', val & 0xFFFFFFFF))
dst3 = dst3[:test_len]
mm3 = 0
for i in range(test_len):
    if test_data[i] != dst3[i]:
        if mm3 < 10:
            gdb.write(f"  [DIFF] off={i}: exp=0x{test_data[i]:02x}('{chr(test_data[i]) if 32<=test_data[i]<=126 else '?'}') got=0x{dst3[i]:02x}('{chr(dst3[i]) if 32<=dst3[i]<=126 else '?'}')\n")
        mm3 += 1
gdb.write(f"[Test3] {'PASS' if mm3 == 0 else 'FAIL'}: {mm3} mismatches out of {test_len} bytes\n")

gdb.write("\n=== All tests complete ===\n")
end

quit
