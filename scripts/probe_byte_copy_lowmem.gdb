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
        if attempt == 3:
            raise
        gdb.write(f"[warn] Attempt {attempt} failed: {err}\n")
        time.sleep(2)
end

monitor halt

python
import gdb, struct

SRC_PA = 0x80F00000
DST_LD_PA = 0x80F00200
DST_SB_PA = 0x80F00400
CODE_PA = 0x81200000

LOWMEM_BASE = 0xffffffd800000000
PA_BASE = 0x80000000

def lowmem_va(pa):
    return LOWMEM_BASE + (pa - PA_BASE)

SRC_VA = lowmem_va(SRC_PA)
DST_LD_VA = lowmem_va(DST_LD_PA)
DST_SB_VA = lowmem_va(DST_SB_PA)
CODE_VA = lowmem_va(CODE_PA)

test_data = b"The quick brown fox jumps over the lazy dog. 0123456789ABCDEF!@#$%^&*()_+" + bytes(range(64))
test_len = len(test_data)
copy_len_aligned = (test_len + 7) & ~7

gdb.write("\n=== Lowmem VA byte-copy probe ===\n")
gdb.write(f"[addr] SRC  PA=0x{SRC_PA:x} VA=0x{SRC_VA:x}\n")
gdb.write(f"[addr] DSTL PA=0x{DST_LD_PA:x} VA=0x{DST_LD_VA:x}\n")
gdb.write(f"[addr] DSTB PA=0x{DST_SB_PA:x} VA=0x{DST_SB_VA:x}\n")
gdb.write(f"[addr] CODE PA=0x{CODE_PA:x} VA=0x{CODE_VA:x}\n")

for i in range(0, test_len + 8, 4):
    chunk = test_data[i:i+4] if i < test_len else b'\x00\x00\x00\x00'
    if len(chunk) < 4:
        chunk = chunk + b'\x00' * (4 - len(chunk))
    val = struct.unpack('<I', chunk)[0]
    gdb.execute(f"set *(unsigned int*)0x{SRC_PA + i:x} = 0x{val:08x}")

for base in (DST_LD_PA, DST_SB_PA):
    for i in range(0, copy_len_aligned + 64, 4):
        gdb.execute(f"set *(unsigned int*)0x{base + i:x} = 0")

ld_sd_instrs = [
    0x0000100f,  # fence.i
    0x00053283,  # ld t0, 0(a0)
    0x0055b023,  # sd t0, 0(a1)
    0x00850513,  # addi a0, a0, 8
    0x00858593,  # addi a1, a1, 8
    0xfec548e3,  # blt a0, a2, -16
    0x00100073,  # ebreak
]

sb_instrs = [
    0x0000100f,  # fence.i
    0x00054283,  # lbu t0, 0(a0)
    0x00558023,  # sb t0, 0(a1)
    0x00150513,  # addi a0, a0, 1
    0x00158593,  # addi a1, a1, 1
    0xfec548e3,  # blt a0, a2, -16
    0x00100073,  # ebreak
]

COPY_LD_PA = CODE_PA + 0x100
COPY_SB_PA = CODE_PA + 0x200
COPY_LD_VA = CODE_VA + 0x100
COPY_SB_VA = CODE_VA + 0x200

for j, val in enumerate(ld_sd_instrs):
    gdb.execute(f"set *(unsigned int*)0x{COPY_LD_PA + j*4:x} = 0x{val:08x}")
for j, val in enumerate(sb_instrs):
    gdb.execute(f"set *(unsigned int*)0x{COPY_SB_PA + j*4:x} = 0x{val:08x}")

# Run ld+sd loop through lowmem VA mapping.
gdb.write("\n=== Test A: lowmem VA ld+sd copy ===\n")
gdb.execute(f"set $a0 = 0x{SRC_VA:x}")
gdb.execute(f"set $a1 = 0x{DST_LD_VA:x}")
gdb.execute(f"set $a2 = 0x{SRC_VA + copy_len_aligned:x}")
gdb.execute(f"set $pc = 0x{COPY_LD_VA:x}")
gdb.execute(f"hbreak *0x{COPY_LD_VA + 24:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")

dst_ld = bytearray()
for i in range(0, copy_len_aligned, 4):
    val = int(gdb.parse_and_eval(f"*(unsigned int*)0x{DST_LD_PA + i:x}"))
    dst_ld.extend(struct.pack('<I', val & 0xFFFFFFFF))
dst_ld = dst_ld[:test_len]
mm_ld = sum(1 for i in range(test_len) if dst_ld[i] != test_data[i])
gdb.write(f"[TestA] {'PASS' if mm_ld == 0 else 'FAIL'}: {mm_ld} mismatches out of {test_len}\n")
if mm_ld:
    shown = 0
    for i in range(test_len):
        if dst_ld[i] != test_data[i]:
            gdb.write(f"  [A DIFF] off={i}: exp=0x{test_data[i]:02x} got=0x{dst_ld[i]:02x}\n")
            shown += 1
            if shown == 10:
                break

# Run lbu+sb loop through lowmem VA mapping.
gdb.write("\n=== Test B: lowmem VA lbu+sb copy ===\n")
gdb.execute(f"set $a0 = 0x{SRC_VA:x}")
gdb.execute(f"set $a1 = 0x{DST_SB_VA:x}")
gdb.execute(f"set $a2 = 0x{SRC_VA + test_len:x}")
gdb.execute(f"set $pc = 0x{COPY_SB_VA:x}")
gdb.execute(f"hbreak *0x{COPY_SB_VA + 24:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")

dst_sb = bytearray()
for i in range(0, test_len + 4, 4):
    val = int(gdb.parse_and_eval(f"*(unsigned int*)0x{DST_SB_PA + i:x}"))
    dst_sb.extend(struct.pack('<I', val & 0xFFFFFFFF))
dst_sb = dst_sb[:test_len]
mm_sb = sum(1 for i in range(test_len) if dst_sb[i] != test_data[i])
gdb.write(f"[TestB] {'PASS' if mm_sb == 0 else 'FAIL'}: {mm_sb} mismatches out of {test_len}\n")
if mm_sb:
    shown = 0
    for i in range(test_len):
        if dst_sb[i] != test_data[i]:
            gdb.write(f"  [B DIFF] off={i}: exp=0x{test_data[i]:02x} got=0x{dst_sb[i]:02x}\n")
            shown += 1
            if shown == 10:
                break

gdb.write("\n=== Probe complete ===\n")
end

quit