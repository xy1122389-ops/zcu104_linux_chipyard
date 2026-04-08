# walk_pt_v2.gdb — Walk SV39 page table via SBA reads
set pagination off
set confirm off
target extended-remote 172.19.128.1:2331

python
import gdb

# swapper_pg_dir VA = 0xffffffff80eca000, PA = VA+0x200000 = 0x810CA000
root_pt_pa = 0x810CA000

# Target VA and expected PA
target_va = 0xffffffff80b02ca0
expected_pa = 0x80d02ca0

# Extract VPN fields
vpn2 = (target_va >> 30) & 0x1FF  # 510
vpn1 = (target_va >> 21) & 0x1FF  # 5
vpn0 = (target_va >> 12) & 0x1FF  # 258
page_off = target_va & 0xFFF      # 0xCA0

gdb.write(f"swapper_pg_dir PA = 0x{root_pt_pa:x}\n")
gdb.write(f"Target VA        = 0x{target_va:016x}\n")
gdb.write(f"Expected PA      = 0x{expected_pa:x}\n")
gdb.write(f"VPN[2]={vpn2} VPN[1]={vpn1} VPN[0]={vpn0} offset=0x{page_off:x}\n\n")

def read_u64(pa):
    val = int(gdb.parse_and_eval(f"*(unsigned long long *)0x{pa:x}"))
    return val & 0xFFFFFFFFFFFFFFFF  # ensure unsigned

# Level 2
l2_addr = root_pt_pa + vpn2 * 8
l2_pte = read_u64(l2_addr)
l2_v = l2_pte & 1
l2_rwx = (l2_pte >> 1) & 7
l2_ppn = (l2_pte >> 10) & 0xFFFFFFFFFFF
gdb.write(f"L2 PTE @ 0x{l2_addr:x} = 0x{l2_pte:016x}\n")
gdb.write(f"  V={l2_v} RWX={l2_rwx:#05b} PPN=0x{l2_ppn:x} → 0x{l2_ppn*4096:x}\n")

if l2_rwx:  # leaf
    pa = (l2_ppn * 4096) | (target_va & 0x3FFFFFFF)
    gdb.write(f"  GIGAPAGE → PA=0x{pa:x}\n")
else:
    # Level 1
    l1_pt = l2_ppn * 4096
    l1_addr = l1_pt + vpn1 * 8
    l1_pte = read_u64(l1_addr)
    l1_v = l1_pte & 1
    l1_rwx = (l1_pte >> 1) & 7
    l1_ppn = (l1_pte >> 10) & 0xFFFFFFFFFFF
    l1_a = (l1_pte >> 5) & 1
    l1_d = (l1_pte >> 6) & 1
    gdb.write(f"L1 PTE @ 0x{l1_addr:x} = 0x{l1_pte:016x}\n")
    gdb.write(f"  V={l1_v} RWX={l1_rwx:#05b} A={l1_a} D={l1_d} PPN=0x{l1_ppn:x} → 0x{l1_ppn*4096:x}\n")

    if l1_rwx:  # leaf = 2MB megapage
        pa = (l1_ppn * 4096) | (target_va & 0x1FFFFF)
        gdb.write(f"  MEGAPAGE → PA=0x{pa:x}\n")
        gdb.write(f"  MATCH={pa == expected_pa}\n\n")
        # Verify data
        gdb.write(f"Data at mapped PA 0x{pa:x}:\n")
        data = []
        for i in range(16):
            b = int(gdb.parse_and_eval(f"*(unsigned char *)0x{pa+i:x}"))
            data.append(b)
        gdb.write("  " + " ".join(f"{b:02x}" for b in data) + "\n")
        gdb.write("  " + "".join(chr(b) if 32<=b<127 else '.' for b in data) + "\n")
        
        gdb.write(f"\nData at expected PA 0x{expected_pa:x}:\n")
        data2 = []
        for i in range(16):
            b = int(gdb.parse_and_eval(f"*(unsigned char *)0x{expected_pa+i:x}"))
            data2.append(b)
        gdb.write("  " + " ".join(f"{b:02x}" for b in data2) + "\n")
        gdb.write("  " + "".join(chr(b) if 32<=b<127 else '.' for b in data2) + "\n")
    else:
        # Level 0
        l0_pt = l1_ppn * 4096
        l0_addr = l0_pt + vpn0 * 8
        l0_pte = read_u64(l0_addr)
        l0_ppn = (l0_pte >> 10) & 0xFFFFFFFFFFF
        gdb.write(f"L0 PTE @ 0x{l0_addr:x} = 0x{l0_pte:016x}\n")
        pa = (l0_ppn * 4096) | page_off
        gdb.write(f"  4KB PAGE → PA=0x{pa:x}\n")
        gdb.write(f"  MATCH={pa == expected_pa}\n")

# Also check badaddr VA mapping
gdb.write(f"\n=== Checking badaddr VA 0xffffff8000000008 ===\n")
bad_va = 0xffffff8000000008
bvpn2 = (bad_va >> 30) & 0x1FF
bvpn1 = (bad_va >> 21) & 0x1FF
bvpn0 = (bad_va >> 12) & 0x1FF
gdb.write(f"VPN[2]={bvpn2} VPN[1]={bvpn1} VPN[0]={bvpn0}\n")
bl2_addr = root_pt_pa + bvpn2 * 8
bl2_pte = read_u64(bl2_addr)
bl2_v = bl2_pte & 1
gdb.write(f"L2 PTE @ 0x{bl2_addr:x} = 0x{bl2_pte:016x} V={bl2_v}\n")

end

quit
