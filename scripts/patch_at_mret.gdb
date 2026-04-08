# patch_at_mret.gdb — Patch strlen AFTER OpenSBI initializes CPU, BEFORE kernel
set pagination off
set confirm off
target extended-remote 172.19.128.1:2331

python
import gdb, time

# Step 1: Boot OpenSBI to get CPU in clean M-mode state
gdb.write("=== Step 1: Boot OpenSBI ===\n")
gdb.execute("set $pc = 0x80000000")
gdb.execute("set $a0 = 0")
gdb.execute("hbreak *0x8000b2b2")  # mret in OpenSBI
gdb.execute("continue")
gdb.write("OpenSBI mret reached — CPU in clean M-mode state\n")
gdb.execute("delete")

# Step 2: Patch strlen via SBA
gdb.write("\n=== Step 2: Patch strlen via SBA ===\n")
base = 0x80651c4c
gdb.execute(f"set *(unsigned int *)0x{base+0x00:x} = 0x00050313")  # mv t1,a0
gdb.execute(f"set *(unsigned int *)0x{base+0x04:x} = 0x00034283")  # lbu t0,0(t1)
gdb.execute(f"set *(unsigned int *)0x{base+0x08:x} = 0x00000013")  # nop [INSERTED]
gdb.execute(f"set *(unsigned int *)0x{base+0x0c:x} = 0x00028663")  # beqz t0,+12
gdb.execute(f"set *(unsigned int *)0x{base+0x10:x} = 0x00130313")  # addi t1,1
new_j = 0xFF5FF06F & ~(1 << 22)  # j -16 instead of j -12  
gdb.execute(f"set *(unsigned int *)0x{base+0x14:x} = 0x{new_j:08x}")  # j -16
gdb.write("SBA writes done\n")

# Step 3: Copyback the patched cache line using CPU (now in clean state)
gdb.write("\n=== Step 3: Copyback strlen patch ===\n")
# Write copyback routine at COPYBACK_ADDR
cb = 0x81200000
gdb.execute(f"set *(unsigned int *)0x{cb+0x00:x} = 0x0000100f")  # fence.i
gdb.execute(f"set *(unsigned int *)0x{cb+0x04:x} = 0x00053283")  # ld t0,0(a0)
gdb.execute(f"set *(unsigned int *)0x{cb+0x08:x} = 0x00553023")  # sd t0,0(a0)
gdb.execute(f"set *(unsigned int *)0x{cb+0x0c:x} = 0x00100073")  # ebreak

# First: dirty the copyback routine itself
for offset in [0, 64]:
    gdb.execute(f"set $a0 = 0x{cb + offset:x}")
    gdb.execute(f"set $pc = 0x{cb:x}")
    gdb.execute(f"hbreak *0x{cb+0x0c:x}")
    gdb.execute("continue")
    gdb.execute("delete")

# Now copyback the strlen patch (2 cache lines covering 0x80651c40-0x80651c7f)
line1 = base & ~63  # 0x80651c40
for line in [line1, line1 + 64]:
    gdb.execute(f"set $a0 = 0x{line:x}")
    gdb.execute(f"set $pc = 0x{cb+4:x}")  # skip fence.i (already done)
    gdb.execute(f"hbreak *0x{cb+0x0c:x}")
    gdb.execute("continue")
    gdb.execute("delete")
gdb.write("Strlen patch copyback complete\n")

# Verify via SBA readback
gdb.write("\n=== Verify patch ===\n")
expected = [0x00050313, 0x00034283, 0x00000013, 0x00028663, 
            0x00130313, new_j, 0x40a30533, 0x00008067]
ok = True
for i in range(8):
    addr = base + i * 4
    val = int(gdb.parse_and_eval(f"*(unsigned int *)0x{addr:x}")) & 0xFFFFFFFF
    exp = expected[i]
    match = "OK" if val == exp else f"MISMATCH (expected 0x{exp:08x})"
    gdb.write(f"  [{i}] 0x{addr:x}: 0x{val:08x} {match}\n")
    if val != exp:
        ok = False

if not ok:
    gdb.write("ERROR: Patch verification failed!\n")
    gdb.execute("quit")

# Step 4: Continue from mret to kernel
gdb.write("\n=== Step 4: Continue to kernel (15s run) ===\n")
gdb.execute(f"set $pc = 0x8000b2b2")  # Resume at mret
# Actually, mret instruction is at 0x8000b2b2, just execute it
# But we need registers set for mret: mepc should point to kernel entry
# Let's check mepc
mepc = int(gdb.parse_and_eval("$mepc"))
gdb.write(f"mepc = 0x{mepc:x}\n")

# Execute mret by continuing from 0x8000b2b2
gdb.execute(f"set $pc = 0x8000b2b2")
gdb.execute("continue &")
time.sleep(15)
gdb.execute("interrupt")

pc = int(gdb.parse_and_eval("$pc"))
gdb.write(f"\nHalted at PC = 0x{pc:016x}\n")

# Step 5: Dump klog
gdb.write("\n=== Step 5: Dump klog ===\n")
gdb.execute("dump binary memory /tmp/klog_nop_patch.bin 0x810D0000 0x81100000")
gdb.write("[ok] Dumped to /tmp/klog_nop_patch.bin\n")

end

quit
