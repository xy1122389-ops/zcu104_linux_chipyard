# jlink_precheck.gdb — Minimal J-Link precheck (no DDR access)
# Tests: connect, halt, read pc, read BootROM, read CLINT
# Does NOT touch DDR, does NOT do large SBA

set confirm off
set pagination off

# Connect to existing J-Link GDB Server on port 3333
target remote :3333

# Try halt
echo \n=== HALT ===\n
monitor halt
echo halt done\n

# Read pc
echo \n=== PC ===\n
print/x $pc

# Read mstatus, mcause, mtvec
echo \n=== CSRs ===\n
print/x $mstatus
print/x $mcause
print/x $mtvec

# Read BootROM at 0x10000 (4 words)
echo \n=== BootROM 0x10000 ===\n
x/4xw 0x10000

# Read CLINT mtime (0x0200BFF8) — TileLink internal, always reachable
echo \n=== CLINT mtime ===\n
x/2xw 0x0200BFF8

# Read Debug Module DMSTATUS via memory (0x0 in debug space — not directly addressable)
# Instead read PLIC priority reg at 0x0C000000 (TileLink, no DDR)
echo \n=== PLIC 0x0C000000 ===\n
x/4xw 0x0C000000

echo \n=== PRECHECK PASSED ===\n
disconnect
quit
