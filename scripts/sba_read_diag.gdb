# sba_read_diag.gdb — Test SBA-write -> CPU-read coherency
# This is the critical path: SBA loads payload into DDR, CPU reads it.
# If the CPU can't see SBA-written data, that explains ALL boot crashes.

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
import gdb, time, struct

gdb.write("\n=== SBA-Write -> CPU-Read Coherency Test ===\n")

# Scratch area well past kernel payload
SCRATCH = 0x8F000000
CODE_BASE = 0x80036200

# Helper: execute one instruction at CODE_BASE, return to ebreak
def cpu_exec_one(insn_word):
    gdb.execute(f"set {{int}}0x{CODE_BASE:x} = {insn_word:#010x}")
    gdb.execute(f"set {{int}}0x{CODE_BASE+4:x} = 0x00100073")  # ebreak
    gdb.execute(f"set $pc = 0x{CODE_BASE:x}")
    gdb.execute("si")  # execute instruction
    gdb.execute("si")  # hit ebreak


# ===== Test 1: SBA writes, CPU reads via ld =====
gdb.write("\n[Test 1] SBA-write -> CPU-read (doubleword)\n")
test_vals = [
    0xDEADBEEFCAFEBABE,
    0x0123456789ABCDEF,
    0xA5A5A5A55A5A5A5A,
    0xFFFFFFFFFFFFFFFF,
    0x0000000000000001,
    0x8000000000000000,
    0x00FF00FF00FF00FF,
    0x1111111111111111,
]

errors = 0
for i, val in enumerate(test_vals):
    addr = SCRATCH + i * 8
    # Step 1: SBA write (via GDB set)
    gdb.execute(f"set {{long}}0x{addr:x} = 0x{val:x}")
    
    # Step 2: CPU reads via ld a1, 0(a0)
    gdb.execute(f"set $a0 = 0x{addr:x}")
    gdb.execute(f"set $a1 = 0xBAD")
    cpu_exec_one(0x00053583)  # ld a1, 0(a0) — opcode for ld a1, 0(a0)
    
    # Step 3: Check a1
    readback = int(gdb.parse_and_eval("$a1"))
    readback &= 0xFFFFFFFFFFFFFFFF
    if readback != val:
        gdb.write(f"  [FAIL] addr=0x{addr:x} expected=0x{val:016x} got=0x{readback:016x}\n")
        errors += 1
    else:
        gdb.write(f"  [OK]   addr=0x{addr:x} val=0x{val:016x}\n")

if errors == 0:
    gdb.write("[PASS] All SBA-write -> CPU-read tests passed (cold cache)\n")
else:
    gdb.write(f"[FAIL] {errors}/{len(test_vals)} SBA-write -> CPU-read failures\n")


# ===== Test 2: SBA write -> CPU read AFTER cache is warm =====
gdb.write("\n[Test 2] SBA-write -> CPU-read (warm D-cache: write then overwrite via SBA)\n")
# This simulates: CPU reads addr → caches the line → SBA overwrites DDR → CPU reads again
# Expected: CPU sees OLD cached value (because D-cache is not invalidated by SBA)
# This would explain boot crashes if kernel data gets cached then SBA can't update it

addr2 = SCRATCH + 0x200
# Step 1: SBA write initial value
gdb.execute(f"set {{long}}0x{addr2:x} = 0xAAAAAAAAAAAAAAAA")

# Step 2: CPU reads it (populates D-cache line)
gdb.execute(f"set $a0 = 0x{addr2:x}")
gdb.execute(f"set $a1 = 0")
cpu_exec_one(0x00053583)  # ld a1, 0(a0)
first_read = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"  First CPU read: 0x{first_read:016x} (expect 0xAAAAAAAAAAAAAAAA)\n")

# Step 3: SBA overwrites with a different value
gdb.execute(f"set {{long}}0x{addr2:x} = 0xBBBBBBBBBBBBBBBB")

# Step 4: CPU reads again (should it see old cached or new SBA value?)
gdb.execute(f"set $a0 = 0x{addr2:x}")
gdb.execute(f"set $a1 = 0")
cpu_exec_one(0x00053583)  # ld a1, 0(a0)
second_read = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"  Second CPU read (after SBA overwrite): 0x{second_read:016x}\n")

if second_read == 0xBBBBBBBBBBBBBBBB:
    gdb.write("  [INFO] D-cache saw SBA update → cache is coherent or line was evicted\n")
elif second_read == 0xAAAAAAAAAAAAAAAA:
    gdb.write("  [INFO] D-cache returned stale value → D-cache NOT coherent with SBA writes\n")
    gdb.write("  [!!!] This means SBA payload restore data can be invisible to CPU if cached!\n")
else:
    gdb.write(f"  [WARN] Unexpected value: 0x{second_read:016x}\n")


# ===== Test 3: SBA write -> CPU read with fence in between =====
gdb.write("\n[Test 3] SBA-write -> fence.i -> CPU-read (fence invalidation)\n")
addr3 = SCRATCH + 0x300
gdb.execute(f"set {{long}}0x{addr3:x} = 0xCCCCCCCCCCCCCCCC")

# CPU reads (cache line)
gdb.execute(f"set $a0 = 0x{addr3:x}")
cpu_exec_one(0x00053583)  # ld a1, 0(a0)
r1 = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF

# SBA overwrite
gdb.execute(f"set {{long}}0x{addr3:x} = 0xDDDDDDDDDDDDDDDD")

# Execute fence.i (invalidates I-cache; may or may not affect D-cache)
cpu_exec_one(0x0000100f)  # fence.i

# Execute fence iorw,iorw
cpu_exec_one(0x0ff0000f)  # fence iorw,iorw

# CPU reads again
gdb.execute(f"set $a0 = 0x{addr3:x}")
cpu_exec_one(0x00053583)  # ld a1, 0(a0)
r2 = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"  Before fence: 0x{r1:016x}, After fence+SBA overwrite: 0x{r2:016x}\n")
if r2 == 0xDDDDDDDDDDDDDDDD:
    gdb.write("  [INFO] Fence made SBA write visible\n")
elif r2 == 0xCCCCCCCCCCCCCCCC:
    gdb.write("  [INFO] Fence did NOT invalidate D-cache for SBA writes\n")


# ===== Test 4: Verify SBA-written payload (actual fw_payload region) =====
gdb.write("\n[Test 4] Verify CPU can read SBA-loaded fw_payload first 64 bytes\n")
# Read first 8 doublewords of fw_payload via SBA
sba_vals = []
for i in range(8):
    v = int(gdb.parse_and_eval(f"*(unsigned long long*)0x{0x80000000 + i*8:x}"))
    sba_vals.append(v)

# Now have CPU read them
cpu_vals = []
for i in range(8):
    addr = 0x80000000 + i * 8
    gdb.execute(f"set $a0 = 0x{addr:x}")
    cpu_exec_one(0x00053583)  # ld a1, 0(a0)
    v = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
    cpu_vals.append(v)

match = True
for i in range(8):
    if sba_vals[i] != cpu_vals[i]:
        gdb.write(f"  [MISMATCH] offset={i*8:#x}: SBA=0x{sba_vals[i]:016x} CPU=0x{cpu_vals[i]:016x}\n")
        match = False
    else:
        gdb.write(f"  [OK] offset={i*8:#x}: 0x{sba_vals[i]:016x}\n")

if match:
    gdb.write("[PASS] CPU reads fw_payload header correctly\n")
else:
    gdb.write("[FAIL] CPU sees different data than SBA for fw_payload!\n")

gdb.write("\n=== SBA Coherency Diagnostic Complete ===\n")
end
