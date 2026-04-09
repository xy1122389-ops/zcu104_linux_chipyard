set pagination off
set confirm off
set remotetimeout 60

target remote 172.19.128.1:12331
monitor halt

python
import gdb, struct, os

# CPU ld reader routine at PA 0x80038000
# fence.i; ld a1, 0(a0); ebreak
READER = 0x80038000

def cpu_ld(pa):
    """Read 8 bytes from physical address via CPU ld (goes through D-cache/L2)"""
    gdb.execute(f"set $a0 = 0x{pa:x}")
    gdb.execute(f"set $pc = 0x{READER + 4:x}")
    gdb.execute(f"hbreak *0x{READER + 8:x}")
    gdb.execute("continue")
    val = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
    gdb.execute("delete breakpoints")
    return val

def sba_rd64(pa):
    """Read 8 bytes from physical address via SBA (bypasses L2)"""
    tmp = "/tmp/_sba.bin"
    gdb.execute(f"dump binary memory {tmp} 0x{pa:x} 0x{pa+8:x}", to_string=True)
    with open(tmp, "rb") as f:
        return struct.unpack("<Q", f.read(8))[0]

# satp = 0x80000000000810CA
# Mode=8 (Sv39), PPN=0x810CA
# Page table root PA = 0x810CA * 4096 = 0x810CA000
SATP = 0x80000000000810CA
PT_ROOT = (SATP & 0xFFFFFFFFFFF) * 4096
gdb.write(f"Page table root PA = 0x{PT_ROOT:x}\n\n")

def sv39_walk(va, use_cpu=False):
    """Walk Sv39 page table for VA, return (PA, level, details)"""
    rd = cpu_ld if use_cpu else sba_rd64
    method = "CPU" if use_cpu else "SBA"
    
    vpn = [(va >> 12) & 0x1FF, (va >> 21) & 0x1FF, (va >> 30) & 0x1FF]
    offset = va & 0xFFF
    
    gdb.write(f"Walk VA=0x{va:016x} via {method}:\n")
    gdb.write(f"  VPN[2]=0x{vpn[2]:03x} VPN[1]=0x{vpn[1]:03x} VPN[0]=0x{vpn[0]:03x} offset=0x{offset:03x}\n")
    
    pt_pa = PT_ROOT
    for level in [2, 1, 0]:
        pte_pa = pt_pa + vpn[level] * 8
        pte = rd(pte_pa)
        
        v = pte & 1
        r = (pte >> 1) & 1
        w = (pte >> 2) & 1
        x = (pte >> 3) & 1
        ppn = (pte >> 10) & 0xFFFFFFFFFFF
        
        gdb.write(f"  L{level}: PTE@0x{pte_pa:x} = 0x{pte:016x}  V={v} R={r} W={w} X={x} PPN=0x{ppn:x}\n")
        
        if not v:
            gdb.write(f"  INVALID PTE at level {level}!\n")
            return None, level, "invalid"
        
        if r or w or x:
            # Leaf PTE
            if level == 2:  # 1GB page
                pa = (ppn << 12) | ((va & 0x3FFFFFFF))
            elif level == 1:  # 2MB page
                pa = (ppn << 12) | ((va & 0x1FFFFF))
            else:  # 4KB page
                pa = (ppn << 12) | offset
            gdb.write(f"  LEAF at L{level}: PA = 0x{pa:x} ({['4KB','2MB','1GB'][level]} page)\n")
            return pa, level, "leaf"
        
        # Non-leaf: next level
        pt_pa = ppn << 12
    
    gdb.write(f"  ERROR: walked to L0 without finding leaf!\n")
    return None, 0, "error"

# Walk key kernel variable VAs
key_vars = [
    ("log_buf", 0xffffffff80cbf368),
    ("log_buf_len", 0xffffffff80cbf360),
    ("__log_buf", 0xffffffff80cd0060),
    ("saved_command_line", 0xffffffff80918468),
    ("oops_count", 0xffffffff80cc0240),
    ("jiffies_64", 0xffffffff80cbf3b0),
    ("system_state", 0xffffffff80cc0038),
    ("init_task", 0xffffffff80c0d740),
]

gdb.write("=" * 60 + "\n")
gdb.write("Sv39 Page Walk Results (SBA reads)\n")
gdb.write("=" * 60 + "\n\n")

for name, va in key_vars:
    pa, level, detail = sv39_walk(va, use_cpu=False)
    if pa is not None:
        # Read via SBA
        sba_val = sba_rd64(pa)
        # Read via CPU ld
        cpu_val = cpu_ld(pa)
        # Also read from the precomputed PA
        precomp_pa = ((va - 0xffffffff80000000 + 0x80200000) & 0xFFFFFFFFFFFFFFFF)
        precomp_val = cpu_ld(precomp_pa) if precomp_pa != pa else cpu_val
        
        eq_str = "==" if sba_val == cpu_val else "!="
        pa_match = "PA_MATCH" if pa == precomp_pa else f"PA_DIFFER(expected=0x{precomp_pa:x})"
        
        gdb.write(f"  >> SBA=0x{sba_val:016x} CPU=0x{cpu_val:016x} {eq_str} | {pa_match}\n")
        if pa != precomp_pa:
            gdb.write(f"  >> Precomp PA val: CPU=0x{precomp_val:016x}\n")
    gdb.write("\n")

# Also walk tp (task_struct) and check
tp = 0xffffffd8014a8000
gdb.write("=" * 60 + "\n")
gdb.write(f"Walk tp (task_struct) VA=0x{tp:016x}\n")
gdb.write("=" * 60 + "\n\n")
pa_tp, _, _ = sv39_walk(tp, use_cpu=False)
if pa_tp is not None:
    comm_offset = 2592  # offsetof(task_struct, comm) is typically around here
    # Try reading first 64 bytes of task_struct
    gdb.write(f"\n  task_struct first 64 bytes at PA=0x{pa_tp:x}:\n")
    for off in range(0, 64, 8):
        v = cpu_ld(pa_tp + off)
        bs = v.to_bytes(8, "little")
        asc = "".join(chr(b) if 32 <= b < 127 else "." for b in bs)
        gdb.write(f"    +0x{off:03x}: 0x{v:016x} [{asc}]\n")

gdb.write("\n[done] Page walk verification complete.\n")
end

quit
