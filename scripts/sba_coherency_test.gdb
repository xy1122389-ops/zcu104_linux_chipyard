# sba_coherency_test.gdb — Minimal SBA coherency verification
# Tests if data written via SBA (GDB restore/set) is visible to the CPU

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

# Initialize core: disable MMU, set dcsr
monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

python
import gdb, struct

gdb.write("\n=== SBA Coherency Verification ===\n")

CODE = 0x80036000
DATA = 0x80038000

# ---- Step 0: Verify SBA round-trip ----
gdb.write("\n[Step 0] SBA write/read round-trip\n")
gdb.execute(f"set {{long}}0x{DATA:x} = 0xCAFEBABEDEADBEEF")
rb = int(gdb.parse_and_eval(f"*(unsigned long long *)0x{DATA:x}"))
rb &= 0xFFFFFFFFFFFFFFFF
gdb.write(f"  Wrote 0xCAFEBABEDEADBEEF, read back 0x{rb:016x}\n")
if rb == 0xCAFEBABEDEADBEEF:
    gdb.write("  [OK] SBA round-trip works\n")
else:
    gdb.write("  [FAIL] SBA round-trip broken!\n")

# ---- Step 1: Write test data ----
gdb.write("\n[Step 1] Write test data via SBA\n")
test_data = [
    0xDEADBEEFCAFEBABE,
    0x0123456789ABCDEF,
    0xA5A5A5A55A5A5A5A,
    0xFFFF0000FFFF0000,
]
for i, val in enumerate(test_data):
    addr = DATA + i * 8
    gdb.execute(f"set {{long}}0x{addr:x} = 0x{val:x}")
    rb = int(gdb.parse_and_eval(f"*(unsigned long long *)0x{addr:x}")) & 0xFFFFFFFFFFFFFFFF
    gdb.write(f"  [SBA] 0x{addr:x} = 0x{rb:016x} {'OK' if rb == val else 'MISMATCH!'}\n")

# ---- Step 2: Build and load tiny test program ----
# Program loads 4 doublewords from DATA into a1-a4, then ebreak
# lui a0, 0x80038     → 0x80038537
# addi a0, a0, 0      → 0x00050513
# ld a1, 0(a0)        → 0x00053583
# ld a2, 8(a0)        → 0x00853603
# ld a3, 16(a0)       → 0x01053683
# ld a4, 24(a0)       → 0x01853703
# ebreak              → 0x00100073

gdb.write("\n[Step 2] Load test code via SBA restore\n")
insns = [0x80038537, 0x00050513, 0x00053583, 0x00853603, 0x01053683, 0x01853703, 0x00100073]
code_bytes = b''.join(struct.pack('<I', w) for w in insns)
code_file = "/tmp/sba_test_code.bin"
with open(code_file, "wb") as f:
    f.write(code_bytes)
gdb.execute(f"restore {code_file} binary 0x{CODE:x}")

# Verify code written
for j in range(len(insns)):
    addr = CODE + j * 4
    rb = int(gdb.parse_and_eval(f"*(unsigned int *)0x{addr:x}")) & 0xFFFFFFFF
    ok = "OK" if rb == insns[j] else "MISMATCH"
    gdb.write(f"  Code[{j}] @ 0x{addr:x}: 0x{rb:08x} (expect 0x{insns[j]:08x}) [{ok}]\n")

# ---- Step 3: Execute via hbreak + continue (si doesn't work on this target) ----
gdb.write("\n[Step 3] Execute test program (hbreak + continue)\n")
gdb.execute("delete breakpoints")
gdb.execute("set $a1 = 0xBAD1")
gdb.execute("set $a2 = 0xBAD2")
gdb.execute("set $a3 = 0xBAD3")
gdb.execute("set $a4 = 0xBAD4")
gdb.execute(f"set $pc = 0x{CODE:x}")

# hbreak at ebreak instruction
ebreak_addr = CODE + (len(insns) - 1) * 4
gdb.write(f"  hbreak at 0x{ebreak_addr:x} (ebreak)\n")
gdb.execute(f"hbreak *0x{ebreak_addr:x}")
gdb.execute("continue")
pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"  Stopped at PC=0x{pc:x}\n")
gdb.execute("delete breakpoints")

# Read final register state
gdb.write("\n[Step 4] Results\n")
regs = {}
for r in ['pc', 'a0', 'a1', 'a2', 'a3', 'a4']:
    v = int(gdb.parse_and_eval(f"${r}")) & 0xFFFFFFFFFFFFFFFF
    regs[r] = v
    gdb.write(f"  {r} = 0x{v:016x}\n")

# ---- Step 5: Compare ----
gdb.write("\n[Step 5] Verify\n")
expected = {'a1': test_data[0], 'a2': test_data[1], 'a3': test_data[2], 'a4': test_data[3]}
all_ok = True
for reg, exp in expected.items():
    got = regs[reg]
    ok = got == exp
    gdb.write(f"  [{('PASS' if ok else 'FAIL')}] {reg}: expect=0x{exp:016x} got=0x{got:016x}\n")
    if not ok:
        all_ok = False

if all_ok:
    gdb.write("\n>>> ALL PASS — SBA writes visible to CPU. Cache coherency is NOT the issue.\n")
else:
    gdb.write("\n>>> FAIL — CPU cannot see SBA-written data. This IS causing boot crashes.\n")

gdb.write("\n=== Test Complete ===\n")
end
