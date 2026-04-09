set pagination off
set confirm off
set remotetimeout 60

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import gdb, os, struct, time, re

host = os.environ.get("JLINK_HOST", "172.19.128.1")
port = int(os.environ.get("JLINK_PORT", "2331"))
gdb.execute(f"target remote {host}:{port}")
gdb.execute("monitor halt")
time.sleep(1)

pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"[state] PC = 0x{pc:016x}\n")

# Read satp
satp_out = gdb.execute("monitor ReadCSR 0x180", to_string=True).strip()
gdb.write(f"[satp] = {satp_out}\n")
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', satp_out)
satp = int(m.group(1), 16) if m else 0

# Parse satp: mode[63:60], ASID[59:44], PPN[43:0]
mode = (satp >> 60) & 0xF
ppn = satp & 0xFFFFFFFFFFF
root_pt = ppn << 12
gdb.write(f"[satp] mode={mode} PPN=0x{ppn:x} root_pt=0x{root_pt:x}\n")

def read8(pa):
    """Read 8 bytes from physical address via dump binary"""
    tmp = f"/tmp/_rd8.bin"
    gdb.execute(f"dump binary memory {tmp} 0x{pa:x} 0x{pa+8:x}", to_string=True)
    with open(tmp, "rb") as f:
        return struct.unpack("<Q", f.read(8))[0]

# Manual SV39 walk for well-known kernel VAs
# VA = 0xffffffff80cbf368 (log_buf)
test_va = 0xffffffff80cbf368
gdb.write(f"\n=== Manual SV39 walk for VA 0x{test_va:x} ===\n")

# SV39 uses bits [38:0] of VA (sign-extended from bit 38)
va_38_0 = test_va & ((1 << 39) - 1)
gdb.write(f"VA[38:0] = 0x{va_38_0:010x}\n")

vpn2 = (va_38_0 >> 30) & 0x1FF
vpn1 = (va_38_0 >> 21) & 0x1FF
vpn0 = (va_38_0 >> 12) & 0x1FF
offset = va_38_0 & 0xFFF
gdb.write(f"vpn[2]={vpn2} vpn[1]={vpn1} vpn[0]={vpn0} offset=0x{offset:03x}\n")

# Level 2: Read PTE from root PT
l2_addr = root_pt + vpn2 * 8
gdb.write(f"\nL2: reading PTE at PA 0x{l2_addr:x} (root+{vpn2}*8)\n")
pte2 = read8(l2_addr)
gdb.write(f"L2 PTE = 0x{pte2:016x}\n")

pte2_v = pte2 & 1
pte2_r = (pte2 >> 1) & 1
pte2_w = (pte2 >> 2) & 1
pte2_x = (pte2 >> 3) & 1
pte2_ppn = (pte2 >> 10) & ((1 << 44) - 1)
gdb.write(f"L2: V={pte2_v} R={pte2_r} W={pte2_w} X={pte2_x} PPN=0x{pte2_ppn:011x}\n")

if pte2_v and (pte2_r or pte2_x):
    # Leaf PTE - 1GB page
    pa = (pte2_ppn << 12) | (va_38_0 & 0x3FFFFFFF)
    gdb.write(f"L2: 1GB LEAF -> PA = 0x{pa:x}\n")
elif pte2_v:
    # Pointer to L1
    l1_base = pte2_ppn << 12
    l1_addr = l1_base + vpn1 * 8
    gdb.write(f"L2: pointer -> L1 base PA = 0x{l1_base:x}\n")
    gdb.write(f"\nL1: reading PTE at PA 0x{l1_addr:x} (l1+{vpn1}*8)\n")
    pte1 = read8(l1_addr)
    gdb.write(f"L1 PTE = 0x{pte1:016x}\n")
    
    pte1_v = pte1 & 1
    pte1_r = (pte1 >> 1) & 1
    pte1_w = (pte1 >> 2) & 1
    pte1_x = (pte1 >> 3) & 1
    pte1_ppn = (pte1 >> 10) & ((1 << 44) - 1)
    gdb.write(f"L1: V={pte1_v} R={pte1_r} W={pte1_w} X={pte1_x} PPN=0x{pte1_ppn:011x}\n")
    
    if pte1_v and (pte1_r or pte1_x):
        # 2MB leaf
        pa = (pte1_ppn << 12) | (va_38_0 & 0x1FFFFF)
        gdb.write(f"L1: 2MB LEAF -> PA = 0x{pa:x}\n")
        
        # Now read the actual data at this PA
        gdb.write(f"\nReading 8 bytes from PA 0x{pa:x}...\n")
        val = read8(pa)
        gdb.write(f"VALUE at VA 0x{test_va:x} (PA 0x{pa:x}) = 0x{val:016x}\n")
    elif pte1_v:
        l0_base = pte1_ppn << 12
        l0_addr = l0_base + vpn0 * 8
        gdb.write(f"L1: pointer -> L0 base PA = 0x{l0_base:x}\n")
        gdb.write(f"\nL0: reading PTE at PA 0x{l0_addr:x}\n")
        pte0 = read8(l0_addr)
        gdb.write(f"L0 PTE = 0x{pte0:016x}\n")
        
        pte0_v = pte0 & 1
        pte0_ppn = (pte0 >> 10) & ((1 << 44) - 1)
        if pte0_v:
            pa = (pte0_ppn << 12) | offset
            gdb.write(f"L0: -> PA = 0x{pa:x}\n")
            val = read8(pa)
            gdb.write(f"VALUE = 0x{val:016x}\n")
else:
    gdb.write(f"L2: INVALID PTE!\n")

# Also do a quick sanity check: read a few PTEs around to see the structure
gdb.write(f"\n=== Root PT dump (last 16 entries: vpn2=496..511) ===\n")
for i in range(496, 512):
    addr = root_pt + i * 8
    pte = read8(addr)
    if pte != 0:
        v = pte & 1
        rwx = ((pte >> 1) & 7)
        ppn = (pte >> 10) & ((1 << 44) - 1)
        gdb.write(f"  PTE[{i:3d}] @ 0x{addr:x} = 0x{pte:016x} V={v} RWX={rwx:03b} PPN=0x{ppn:x}\n")

# Sanity: read some known raw PAs to verify SBA works
gdb.write(f"\n=== SBA sanity checks ===\n")
# OpenSBI magic at PA 0x80000000 (should be known code)
gdb.write(f"PA 0x80000000 (OpenSBI entry): 0x{read8(0x80000000):016x}\n")
# Linux Image start at PA 0x80200000 (should be MZ header)
gdb.write(f"PA 0x80200000 (Image start): 0x{read8(0x80200000):016x}\n")
# DTB at PA 0x84000000 (should be FDT magic 0xd00dfeed)
gdb.write(f"PA 0x84000000 (DTB magic): 0x{read8(0x84000000):016x}\n")

# Directly try reading kernel data using the PA from the 2MB page formula
# For kernel text mapping: VA 0xffffffff80000000 maps to PA 0x80200000
# This means the kernel uses PA_OFFSET = 0x80200000 for its linear mapping
# For a 2MB page: VA 0xffffffff80c00000 -> PA 0x80e00000 (0xc00000 + 0x200000)
pa_logbuf = 0x80200000 + 0xcbf368  # = 0x80ebf368
gdb.write(f"\nDirect PA read (log_buf @ 0x{pa_logbuf:x}): 0x{read8(pa_logbuf):016x}\n")

# Try reading 64 bytes around log_buf PA to see the context
gdb.write(f"\nHex dump around PA 0x80ebf360:\n")
for off in range(0, 64, 8):
    addr = 0x80ebf360 + off
    val = read8(addr)
    gdb.write(f"  0x{addr:x}: 0x{val:016x}\n")

gdb.write("\n[done]\n")
end

quit
