# patch_strlen_nop.gdb — Patch strlen with NOP between lbu and beqz
# Tests whether the kernel crash is caused by a Rocket pipeline hazard
# in the load→branch forwarding path.
set pagination off
set confirm off
target extended-remote 172.19.128.1:2331

python
import gdb

# strlen is at VA 0xffffffff80451c4c → PA 0x80651c4c
# Original code:
#   0x..4c: 00000013  nop
#   0x..50: 00050313  mv   t1, a0
#   0x..54: 00034283  lbu  t0, 0(t1)    ← loop start
#   0x..58: 00028663  beqz t0, +12 → 0x..64
#   0x..5c: 00130313  addi t1, t1, 1
#   0x..60: ff5ff06f  j    -12 → 0x..54
#   0x..64: 40a30533  sub  a0, t1, a0
#   0x..68: 00008067  ret
#
# Patched code (NOP between lbu and beqz):
#   0x..4c: 00050313  mv   t1, a0       (moved up from 0x50)
#   0x..50: 00034283  lbu  t0, 0(t1)    ← loop start (moved from 0x54)
#   0x..54: 00000013  nop               ← INSERTED: pipeline bubble
#   0x..58: 00028663  beqz t0, +12 → 0x..64  (target unchanged!)
#   0x..5c: 00130313  addi t1, t1, 1    (unchanged)
#   0x..60: ????????  j    -16 → 0x..50  (was j -12, now goes to new loop start)
#   0x..64: 40a30533  sub  a0, t1, a0   (unchanged)
#   0x..68: 00008067  ret               (unchanged)

base_pa = 0x80651c4c

# Write patched instructions via SBA
gdb.write("=== Patching strlen at PA 0x80651c4c ===\n")

# 0x4c: mv t1, a0
gdb.execute(f"set *(unsigned int *)0x{base_pa + 0:x} = 0x00050313")
gdb.write("  0x4c: mv t1, a0\n")

# 0x50: lbu t0, 0(t1)
gdb.execute(f"set *(unsigned int *)0x{base_pa + 4:x} = 0x00034283")
gdb.write("  0x50: lbu t0, 0(t1)  [loop start]\n")

# 0x54: nop (pipeline bubble)
gdb.execute(f"set *(unsigned int *)0x{base_pa + 8:x} = 0x00000013")
gdb.write("  0x54: nop  [INSERTED]\n")

# 0x58: beqz t0, +12 (target = 0x64, same as before)
# Already correct, but write it anyway for safety
gdb.execute(f"set *(unsigned int *)0x{base_pa + 0xc:x} = 0x00028663")
gdb.write("  0x58: beqz t0, +12\n")

# 0x5c: addi t1, t1, 1 (unchanged)
gdb.execute(f"set *(unsigned int *)0x{base_pa + 0x10:x} = 0x00130313")
gdb.write("  0x5c: addi t1, t1, 1\n")

# 0x60: j -16 (to 0x50)
# Encoding: compute manually
# Original j -12 = 0xff5ff06f
# For j -16: need to encode JAL x0, -16
# Using formula: offset -16, change imm[2] from 1 to 0
# imm[2] is in encoding bit 22
# 0xff5ff06f has bit22=1, clear it:
# 0xff5ff06f & ~(1<<22) = 0xff5ff06f & 0xFFBFFFFF = 0xFF1FF06F
new_j = 0xFF5FF06F & ~(1 << 22)
gdb.execute(f"set *(unsigned int *)0x{base_pa + 0x14:x} = 0x{new_j:08x}")
gdb.write(f"  0x60: j -16 (0x{new_j:08x})\n")

# 0x64-0x68: unchanged (sub and ret)
# Already correct in memory

# Now copyback this cache line to ensure it's dirty in L2
# The cache line at PA 0x80651c40 (64-byte aligned)
line_pa = base_pa & ~63  # 0x80651c40
gdb.write(f"\n[copyback] Dirtying cache line at 0x{line_pa:x}\n")

# Write copyback routine at COPYBACK_ADDR PA 0x81200000
cb = 0x81200000
gdb.execute(f"set *(unsigned int *)0x{cb:x} = 0x0000100f")    # fence.i
gdb.execute(f"set *(unsigned int *)0x{cb+4:x} = 0x00053283")  # ld t0, 0(a0)
gdb.execute(f"set *(unsigned int *)0x{cb+8:x} = 0x00553023")  # sd t0, 0(a0)
gdb.execute(f"set *(unsigned int *)0x{cb+0xc:x} = 0x00100073") # ebreak

# Dirty the copyback code itself
gdb.execute(f"set $a0 = 0x{cb:x}")
gdb.execute(f"set $a1 = 0x{cb + 64:x}")
gdb.execute(f"set $pc = 0x{cb:x}")  # fence.i first
gdb.execute(f"hbreak *0x{cb + 0xc:x}")  # break at ebreak
gdb.execute("continue")
gdb.execute("delete")
gdb.write("[copyback] Routine ready\n")

# Now copyback the strlen patch line
gdb.execute(f"set $a0 = 0x{line_pa:x}")
gdb.execute(f"set $pc = 0x{cb:x}")   # fence.i + ld + sd + ebreak
gdb.execute(f"hbreak *0x{cb + 0xc:x}")
gdb.execute("continue")
gdb.execute("delete")

# Also copyback the next cache line (strlen continues past 64 bytes)
next_line = line_pa + 64
gdb.execute(f"set $a0 = 0x{next_line:x}")
gdb.execute(f"set $pc = 0x{cb:x}")
gdb.execute(f"hbreak *0x{cb + 0xc:x}")
gdb.execute("continue")
gdb.execute("delete")
gdb.write("[copyback] strlen patch lines dirtied\n")

# Verify the patch by reading back
gdb.write("\n=== Verifying patch via SBA readback ===\n")
for i in range(8):
    addr = base_pa + i * 4
    val = int(gdb.parse_and_eval(f"*(unsigned int *)0x{addr:x}"))
    gdb.write(f"  PA 0x{addr:x}: 0x{val & 0xFFFFFFFF:08x}\n")

# Now restart from OpenSBI
gdb.write("\n=== Restarting from OpenSBI with patched strlen ===\n")
gdb.execute("set $pc = 0x80000000")
gdb.execute("set $a0 = 0")

# Break at mret
gdb.execute("hbreak *0x8000b2b2")
gdb.execute("continue")
gdb.write("OpenSBI mret reached\n")

a0_val = int(gdb.parse_and_eval("$a0"))
a1_val = int(gdb.parse_and_eval("$a1"))
gdb.write(f"  a0={a0_val:#x} a1={a1_val:#x}\n")
gdb.execute("delete")

# Let kernel run for 15 seconds
import time
gdb.execute("continue &")
time.sleep(15)
gdb.execute("interrupt")

pc = int(gdb.parse_and_eval("$pc"))
gdb.write(f"\nHalted at PC={pc:#018x}\n")

# Dump klog
gdb.execute("dump binary memory /tmp/klog_nop_patch.bin 0x810D0000 0x81100000")
gdb.write("[ok] klog dumped to /tmp/klog_nop_patch.bin\n")

end

quit
