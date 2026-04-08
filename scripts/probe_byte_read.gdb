# probe_byte_read.gdb — Read a single byte through the CPU at the target VA
# This bypasses strlen and directly tests if the CPU can see the NUL byte
set pagination off
set confirm off
target extended-remote 172.19.128.1:2331

python
import gdb

# First halt the CPU (it might be running strlen from previous test)
# GDB should have halted it on connect

pc = int(gdb.parse_and_eval("$pc"))
gdb.write(f"Current PC: {pc:#018x}\n")

# We need to execute a single lbu instruction through the CPU
# to read what the CPU's DCache/TLB actually sees.
# 
# Strategy: Write a small probe at COPYBACK_ADDR (PA 0x81200000)
# which corresponds to lowmem VA 0xffffffd801200000
# 
# Probe:
#   lbu a0, 0(a0)    # 0x00054503 — read byte at address in a0
#   ebreak            # 0x00100073 — trap back to debugger
#
# Note: We write via SBA, then need fence.i before CPU can fetch.
# But we can't easily do fence.i from GDB... 
# Instead, we'll use a region that's already mapped and executable.
#
# Actually, the strlen code itself does lbu! Let's just:
# 1. Set a0 = target_va
# 2. Set t1 = a0  (or just set both)
# 3. Set PC to the lbu instruction in strlen (0xffffffff80451c54)
# 4. Single-step ONE instruction
# 5. Read t0 (the loaded byte)

test_va = 0xffffffff80b02ca0  # "bus\0" string

gdb.write(f"\n=== Single-byte CPU read test ===\n")
gdb.write(f"Reading byte at VA {test_va:#x} through CPU's DCache/TLB\n\n")

# Test multiple bytes: 0-7
for offset in range(8):
    addr = test_va + offset
    
    # Set t1 = addr (strlen uses t1 as the pointer)
    gdb.execute(f"set $t1 = {addr:#x}")
    # Set PC to the lbu instruction: lbu t0, 0(t1)
    gdb.execute(f"set $pc = 0xffffffff80451c54")
    
    # Single-step one instruction
    gdb.execute("stepi")
    
    # Read t0 (the loaded byte value)
    t0 = int(gdb.parse_and_eval("$t0")) & 0xFF
    new_pc = int(gdb.parse_and_eval("$pc"))
    
    gdb.write(f"  VA {addr:#x}: byte=0x{t0:02x} ('{chr(t0) if 32<=t0<127 else '.'}')  PC after={new_pc:#x}\n")

# Also read the same bytes via SBA for comparison
gdb.write(f"\n=== SBA (bypass cache) read for comparison ===\n")
pa = 0x80d02ca0
for offset in range(8):
    addr = pa + offset
    b = int(gdb.parse_and_eval(f"*(unsigned char *){addr:#x}"))
    gdb.write(f"  PA {addr:#x}: byte=0x{b:02x} ('{chr(b) if 32<=b<127 else '.'}')\n")

gdb.write(f"\n=== Also test lowmem VA mapping ===\n")
lowmem_va = 0xffffffd800d02ca0
for offset in range(8):
    addr = lowmem_va + offset
    gdb.execute(f"set $t1 = {addr:#x}")
    gdb.execute(f"set $pc = 0xffffffff80451c54")
    gdb.execute("stepi")
    t0 = int(gdb.parse_and_eval("$t0")) & 0xFF
    gdb.write(f"  VA {addr:#x}: byte=0x{t0:02x} ('{chr(t0) if 32<=t0<127 else '.'}')\n")

end

quit
