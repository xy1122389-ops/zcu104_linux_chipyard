# walk_pagetable.gdb — Walk SV39 page table to verify VA→PA mapping
# Check if VA 0xffffffff80b02ca0 maps to the correct PA 0x80D02CA0
set pagination off
set confirm off
target extended-remote 172.19.128.1:2331

python
import gdb

# Target VA to check
target_va = 0xffffffff80b02ca0
expected_pa = 0x80d02ca0

# Read satp (supervisor address translation and protection)
# satp format: MODE(4) | ASID(16) | PPN(44)
satp_val = int(gdb.parse_and_eval("$satp"))
gdb.write(f"satp = 0x{satp_val:016x}\n")

mode = (satp_val >> 60) & 0xF
asid = (satp_val >> 44) & 0xFFFF
ppn = satp_val & 0xFFFFFFFFFFF  # 44 bits

gdb.write(f"  MODE={mode} (8=SV39, 9=SV48)\n")
gdb.write(f"  ASID={asid}\n")
gdb.write(f"  PPN=0x{ppn:011x} → root PT PA=0x{ppn * 4096:016x}\n")

if mode != 8:
    gdb.write(f"ERROR: Expected SV39 (mode=8), got mode={mode}\n")
    gdb.execute("quit")

root_pt_pa = ppn * 4096

# Extract VPN fields from target VA
vpn2 = (target_va >> 30) & 0x1FF  # bits 38:30
vpn1 = (target_va >> 21) & 0x1FF  # bits 29:21
vpn0 = (target_va >> 12) & 0x1FF  # bits 20:12
page_off = target_va & 0xFFF

gdb.write(f"\nTarget VA: 0x{target_va:016x}\n")
gdb.write(f"  VPN[2]={vpn2} (0x{vpn2:03x})\n")
gdb.write(f"  VPN[1]={vpn1} (0x{vpn1:03x})\n")
gdb.write(f"  VPN[0]={vpn0} (0x{vpn0:03x})\n")
gdb.write(f"  Page offset=0x{page_off:03x}\n")

def read_u64(addr):
    """Read 8 bytes from physical address via SBA"""
    return int(gdb.parse_and_eval(f"*(unsigned long long *){addr}"))

def parse_pte(pte_val):
    """Parse SV39 PTE fields"""
    v = pte_val & 1
    r = (pte_val >> 1) & 1
    w = (pte_val >> 2) & 1
    x = (pte_val >> 3) & 1
    u = (pte_val >> 4) & 1
    a = (pte_val >> 5) & 1
    d = (pte_val >> 6) & 1
    ppn = (pte_val >> 10) & 0xFFFFFFFFFFF  # 44 bits
    flags = f"V={v} R={r} W={w} X={x} U={u} A={a} D={d}"
    is_leaf = (r or w or x) and v
    return ppn, flags, is_leaf, v

# Level 2: read root PT entry at VPN[2]
l2_pte_addr = root_pt_pa + vpn2 * 8
l2_pte = read_u64(l2_pte_addr)
l2_ppn, l2_flags, l2_leaf, l2_valid = parse_pte(l2_pte)
gdb.write(f"\nLevel-2 PTE @ PA 0x{l2_pte_addr:x}:\n")
gdb.write(f"  PTE = 0x{l2_pte:016x}\n")
gdb.write(f"  {l2_flags}\n")
gdb.write(f"  PPN = 0x{l2_ppn:011x} → PA 0x{l2_ppn * 4096:x}\n")
gdb.write(f"  Leaf={l2_leaf} (1GB megapage if leaf)\n")

if not l2_valid:
    gdb.write("ERROR: Level-2 PTE not valid!\n")
    gdb.execute("quit")

if l2_leaf:
    # 1GB gigapage mapping
    final_pa = (l2_ppn << 12) | ((target_va) & 0x3FFFFFFF)
    gdb.write(f"\n=== 1GB GIGAPAGE: VA 0x{target_va:x} → PA 0x{final_pa:x} ===\n")
    gdb.write(f"Expected PA: 0x{expected_pa:x}\n")
    gdb.write(f"Match: {final_pa == expected_pa}\n")
    gdb.execute("quit")

# Level 1: read from next level PT
l1_pt_pa = l2_ppn * 4096
l1_pte_addr = l1_pt_pa + vpn1 * 8
l1_pte = read_u64(l1_pte_addr)
l1_ppn, l1_flags, l1_leaf, l1_valid = parse_pte(l1_pte)
gdb.write(f"\nLevel-1 PTE @ PA 0x{l1_pte_addr:x}:\n")
gdb.write(f"  PTE = 0x{l1_pte:016x}\n")
gdb.write(f"  {l1_flags}\n")
gdb.write(f"  PPN = 0x{l1_ppn:011x} → PA 0x{l1_ppn * 4096:x}\n")
gdb.write(f"  Leaf={l1_leaf} (2MB megapage if leaf)\n")

if not l1_valid:
    gdb.write("ERROR: Level-1 PTE not valid!\n")
    gdb.execute("quit")

if l1_leaf:
    # 2MB megapage mapping
    final_pa = (l1_ppn << 12) | ((target_va) & 0x1FFFFF)
    gdb.write(f"\n=== 2MB MEGAPAGE: VA 0x{target_va:x} → PA 0x{final_pa:x} ===\n")
    gdb.write(f"Expected PA: 0x{expected_pa:x}\n")
    gdb.write(f"Match: {final_pa == expected_pa}\n")
    
    # Read the actual data the CPU would see
    gdb.write(f"\n[verify] Reading data at mapped PA 0x{final_pa:x}:\n")
    gdb.execute(f"x/4s 0x{final_pa:x}")
    
    gdb.write(f"\n[verify] Reading data at expected PA 0x{expected_pa:x}:\n")
    gdb.execute(f"x/4s 0x{expected_pa:x}")
    
    gdb.execute("quit")

# Level 0: read from leaf PT
l0_pt_pa = l1_ppn * 4096
l0_pte_addr = l0_pt_pa + vpn0 * 8
l0_pte = read_u64(l0_pte_addr)
l0_ppn, l0_flags, l0_leaf, l0_valid = parse_pte(l0_pte)
gdb.write(f"\nLevel-0 PTE @ PA 0x{l0_pte_addr:x}:\n")
gdb.write(f"  PTE = 0x{l0_pte:016x}\n")
gdb.write(f"  {l0_flags}\n")
gdb.write(f"  PPN = 0x{l0_ppn:011x} → PA 0x{l0_ppn * 4096:x}\n")

if not l0_valid:
    gdb.write("ERROR: Level-0 PTE not valid!\n")
    gdb.execute("quit")

final_pa = (l0_ppn * 4096) | page_off
gdb.write(f"\n=== 4KB PAGE: VA 0x{target_va:x} → PA 0x{final_pa:x} ===\n")
gdb.write(f"Expected PA: 0x{expected_pa:x}\n")
gdb.write(f"Match: {final_pa == expected_pa}\n")

gdb.write(f"\n[verify] Reading data at mapped PA 0x{final_pa:x}:\n")
gdb.execute(f"x/4s 0x{final_pa:x}")

gdb.write(f"\n[verify] Reading data at expected PA 0x{expected_pa:x}:\n")
gdb.execute(f"x/4s 0x{expected_pa:x}")

end

quit
