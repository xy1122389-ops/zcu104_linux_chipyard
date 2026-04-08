# probe_strlen.gdb — Use the CPU itself to call strlen and verify its behavior
# This tests whether the CPU can correctly see the NUL byte at VA 0xffffffff80b02ca3
set pagination off
set confirm off
target extended-remote 172.19.128.1:2331

python
import gdb

# strlen is at VA 0xffffffff80451c4c
# strlen+0x18 (ret) is at 0xffffffff80451c68
strlen_entry = 0xffffffff80451c4c
strlen_ret   = 0xffffffff80451c68

# Target string "bus\0" at VA 0xffffffff80b02ca0
test_va = 0xffffffff80b02ca0

# Save current CPU state
saved = {}
for r in ['pc', 'ra', 'sp', 'a0', 't0', 't1', 't3']:
    saved[r] = int(gdb.parse_and_eval(f"${r}"))
gdb.write("Saved registers\n")

# Also try reading the byte at the target VA directly
# We'll write a tiny probe: lbu t0, 0(a0); ebreak
# Place it at a safe address. 
# Current tp (thread pointer) area... no, let's use kernel stack area.
# Actually, let's just call strlen directly:

gdb.write(f"\n=== Test 1: CPU strlen(\"{test_va:#x}\") ===\n")
gdb.execute(f"set $a0 = {test_va:#x}")
gdb.execute(f"set $pc = {strlen_entry:#x}")
gdb.execute(f"hbreak *{strlen_ret:#x}")
gdb.execute("continue")

# Read results
result_a0 = int(gdb.parse_and_eval("$a0"))
result_t1 = int(gdb.parse_and_eval("$t1"))
pc_now = int(gdb.parse_and_eval("$pc"))
gdb.write(f"PC = {pc_now:#x}\n")
gdb.write(f"strlen result (a0) = {result_a0} (expected: 3 for 'bus')\n")
gdb.write(f"t1 (final scan pos) = {result_t1:#x}\n")
gdb.write(f"t1 - test_va = {result_t1 - test_va} bytes scanned\n")

# Delete the breakpoint
gdb.execute("delete")

# Test 2: Try a known-good string - the kernel command line in .rodata
# "earlycon" should be somewhere
# Let's use a string we know: test with lowmem VA mapping
# PA 0x80d02ca0 → lowmem VA = 0xffffffd800000000 + (0x80d02ca0 - 0x80000000)
#                             = 0xffffffd800d02ca0
lowmem_va = 0xffffffd800d02ca0
gdb.write(f"\n=== Test 2: CPU strlen({lowmem_va:#x}) (lowmem VA for same PA) ===\n")
gdb.execute(f"set $a0 = {lowmem_va:#x}")
gdb.execute(f"set $pc = {strlen_entry:#x}")
gdb.execute(f"hbreak *{strlen_ret:#x}")
gdb.execute("continue")

result_a0 = int(gdb.parse_and_eval("$a0"))
result_t1 = int(gdb.parse_and_eval("$t1"))
gdb.write(f"strlen result (a0) = {result_a0} (expected: 3 for 'bus')\n")
gdb.write(f"t1 (final scan pos) = {result_t1:#x}\n")

gdb.execute("delete")

# Test 3: Read the actual bytes at the target VA one by one
# Write a probe that loads 8 bytes and stores to known location
gdb.write(f"\n=== Test 3: CPU byte-by-byte read at {test_va:#x} ===\n")
# We'll read 8 bytes by repeatedly doing lbu
for i in range(8):
    addr = test_va + i
    # Set a0 to address, set PC to the lbu instruction in strlen
    # Actually, just use the GDB x command... no that goes through SBA
    # We need to execute on the CPU. Let's do it hacky:
    # Write tiny code: lbu a0, 0(a0); ebreak
    # lbu a0, 0(a0) = 0x00054503  
    # ebreak        = 0x00100073
    
    # Place at lowmem mapping of COPYBACK_ADDR
    # PA 0x81200000 → lowmem VA 0xffffffd801200000
    probe_pa = 0x81200000
    probe_va = 0xffffffd801200000
    
    if i == 0:
        # Write the probe code via SBA
        gdb.execute(f"set *(unsigned int *)0x{probe_pa:x} = 0x00054503")  # lbu a0, 0(a0)
        gdb.execute(f"set *(unsigned int *)0x{probe_pa+4:x} = 0x00100073")  # ebreak
        # Need fence.i to sync icache
        gdb.execute(f"set *(unsigned int *)0x{probe_pa+8:x} = 0x0000100f")  # fence.i
        # Actually execute fence.i first before running probe
        gdb.execute(f"set $pc = {probe_va+8:#x}")  # fence.i
        gdb.execute(f"hbreak *{probe_va:#x}")       # break at lbu
        gdb.execute("continue")
        gdb.execute("delete")
    
    gdb.execute(f"set $a0 = {addr:#x}")
    gdb.execute(f"set $pc = {probe_va:#x}")  # lbu a0, 0(a0)
    gdb.execute(f"hbreak *{probe_va+4:#x}")  # break at ebreak
    gdb.execute("continue")
    
    byte_val = int(gdb.parse_and_eval("$a0")) & 0xFF
    gdb.write(f"  [{i}] VA {addr:#x}: 0x{byte_val:02x} ('{chr(byte_val) if 32<=byte_val<127 else '.'}')\n")
    gdb.execute("delete")

# Restore registers
gdb.write(f"\nRestoring CPU state...\n")
for r, v in saved.items():
    gdb.execute(f"set ${r} = {v:#x}")

gdb.write("\n=== Probe complete ===\n")

end

quit
