# SDHCI Smoke Test via J-Link GDB SBA
# Tests PL→PS LPD path (S_AXI_LPD / saxigp6)
# Reads SDHCI controller registers at Rocket address 0x6017xxxx
# (maps to PS 0xFF17xxxx via A2 route)

set confirm off
set pagination off
set architecture riscv:rv64

python
import os, gdb, time

_host = os.environ.get("JLINK_HOST", "172.19.128.1")
_port = int(os.environ.get("JLINK_PORT", "12331"))
gdb.execute(f"target remote {_host}:{_port}")
gdb.execute("monitor halt")
time.sleep(1)

gdb.write("\n=== SDHCI Smoke Test (A2 Route: PL→PS LPD via saxigp6) ===\n\n")

# Ensure satp=0 (no MMU) for clean SBA access
gdb.execute("monitor WriteCSR 0x180 0")
gdb.write("[setup] satp cleared (M-mode, no MMU)\n")

# SDHCI register map (Rocket addresses, maps to PS 0xFF17xxxx):
#   0x601700FC = Host Controller Version / Slot Interrupt Status
#   0x60170040 = Capabilities Register (low 32 bits)
#   0x60170044 = Capabilities Register (high 32 bits)
#   0x60170024 = Present State Register
#   0x6017002C = Clock Control / Timeout Control / Software Reset

regs = [
    ("SDHCI_VERSION  (0x601700FC)", 0x601700FC),
    ("SDHCI_CAPS_LO  (0x60170040)", 0x60170040),
    ("SDHCI_CAPS_HI  (0x60170044)", 0x60170044),
    ("SDHCI_PRESENT  (0x60170024)", 0x60170024),
    ("SDHCI_CLK_CTRL (0x6017002C)", 0x6017002C),
]

all_ok = True
results = []

for name, addr in regs:
    try:
        val = int(gdb.parse_and_eval(f"*(unsigned int*)0x{addr:x}"))
        results.append((name, addr, val, True))
        gdb.write(f"  {name} = 0x{val:08X}\n")
    except Exception as err:
        results.append((name, addr, 0, False))
        gdb.write(f"  {name} = ERROR: {err}\n")
        all_ok = False

gdb.write("\n--- Analysis ---\n")

# Check version register
for name, addr, val, ok in results:
    if addr == 0x601700FC and ok:
        spec_ver = (val >> 16) & 0xFF
        vendor_ver = (val >> 24) & 0xFF
        slot_int = val & 0xFFFF
        gdb.write(f"  Spec version  : {spec_ver} ")
        if spec_ver == 0:
            gdb.write("(SD Host Spec 1.0)\n")
        elif spec_ver == 1:
            gdb.write("(SD Host Spec 2.0)\n")
        elif spec_ver == 2:
            gdb.write("(SD Host Spec 3.0)\n")
        elif spec_ver == 3:
            gdb.write("(SD Host Spec 4.0)\n")
        else:
            gdb.write(f"(unknown)\n")
        gdb.write(f"  Vendor version: {vendor_ver}\n")

    if addr == 0x60170040 and ok:
        max_blk = (val >> 16) & 0x3
        base_clk = (val >> 8) & 0xFF
        gdb.write(f"  Base clock    : {base_clk} MHz\n")
        gdb.write(f"  Max block len : {512 << max_blk} bytes\n")

if all_ok:
    # Check if any register returned all zeros (might indicate bus not connected)
    all_zero = all(val == 0 for _, _, val, ok in results if ok)
    if all_zero:
        gdb.write("\n[WARN] All registers are 0x00000000 - bus may not be connected or XPPU blocking\n")
    else:
        gdb.write("\n[PASS] SDHCI registers readable via A2 route!\n")
else:
    gdb.write("\n[FAIL] Some register reads failed - bus error or path not functional\n")

gdb.write("\n=== SDHCI Smoke Test Complete ===\n")
end

quit
