set pagination off
set confirm off
set breakpoint auto-hw off
set remotetimeout 600

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import gdb, os, time
host = os.environ.get("JLINK_HOST", "172.19.128.1")
port = int(os.environ.get("JLINK_PORT", "2331"))
gdb.write(f"[info] Connecting to J-Link at {host}:{port}\n")
last_error = None
for attempt in range(1, 4):
    try:
        gdb.execute(f"target remote {host}:{port}")
        gdb.write(f"[info] Connected on attempt {attempt}\n")
        last_error = None
        break
    except gdb.error as err:
        last_error = err
        gdb.write(f"[warn] Attempt {attempt} failed: {err}\n")
        if attempt < 3:
            time.sleep(2)
if last_error is not None:
    raise last_error
end

monitor halt
echo --- Initial state ---\n
info reg pc
monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

echo \n=== Phase 1: Restore fw_payload.bin (interleaved SBA + L2 copyback) ===\n
python
import os, gdb, time

# --- L2 cache parameters ---
# SiFive InclusiveCache: 512KB, 8-way, 1024 sets, 64B lines = 8192 lines total
# SBA writes create CLEAN L2 lines lost on eviction.
# Strategy: write 256KB via SBA, then immediately copyback (ld+sd) to make dirty.
# 256KB = 4096 lines = 4 lines/set (out of 8 ways), safe from self-eviction.

COPYBACK_ADDR = 0x81200000
SUB_CHUNK = 256 * 1024  # 256KB sub-chunks for interleaved write+copyback

# Write the copyback routine via SBA (6 instructions = 24 bytes)
instrs = [
    (COPYBACK_ADDR + 0x00, 0x0000100f),  # fence.i
    (COPYBACK_ADDR + 0x04, 0x00053283),  # ld t0, 0(a0)
    (COPYBACK_ADDR + 0x08, 0x00553023),  # sd t0, 0(a0)
    (COPYBACK_ADDR + 0x0C, 0x04050513),  # addi a0, a0, 64
    (COPYBACK_ADDR + 0x10, 0xFEB54AE3),  # blt a0, a1, -12
    (COPYBACK_ADDR + 0x14, 0x00100073),  # ebreak
]
for addr, val in instrs:
    gdb.execute(f"set *(unsigned int*)0x{addr:x} = 0x{val:08x}")

# Copyback the routine itself (1 cache line) so it survives
gdb.execute(f"set $a0 = 0x{COPYBACK_ADDR:x}")
gdb.execute(f"set $a1 = 0x{COPYBACK_ADDR + 64:x}")
gdb.execute(f"set $pc = 0x{COPYBACK_ADDR:x}")   # starts with fence.i
gdb.execute(f"hbreak *0x{COPYBACK_ADDR + 0x14:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.write("[copyback] Routine at 0x{:08x} written and dirtied\n".format(COPYBACK_ADDR))

# Helper: run copyback on [start_addr, end_addr_aligned)
first_copyback = [True]  # use fence.i only on first call
def run_copyback(start, end_aligned):
    n = (end_aligned - start) // 64
    entry = COPYBACK_ADDR if first_copyback[0] else COPYBACK_ADDR + 4
    first_copyback[0] = False
    gdb.execute(f"set $a0 = 0x{start:x}")
    gdb.execute(f"set $a1 = 0x{end_aligned:x}")
    gdb.execute(f"set $pc = 0x{entry:x}")
    gdb.execute(f"hbreak *0x{COPYBACK_ADDR + 0x14:x}")
    gdb.execute("continue")
    a0_after = int(gdb.parse_and_eval("$a0")) & 0xFFFFFFFFFFFFFFFF
    gdb.execute("delete breakpoints")
    if a0_after < end_aligned:
        gdb.write(f"[WARN] copyback incomplete: a0=0x{a0_after:x} expected 0x{end_aligned:x}\n")

# --- Load payload with interleaved copyback ---
chunk_dir = "/tmp/fw_chunks_allpatch"
base_addr = 0x80000000
chunk_size = 4194304  # 4MB per file chunk
chunks = sorted([f for f in os.listdir(chunk_dir) if f.startswith("chunk_") and f.endswith(".bin")])

total_size = sum(os.path.getsize(os.path.join(chunk_dir, f)) for f in chunks)
total_sub = 0
for f in chunks:
    total_sub += (os.path.getsize(os.path.join(chunk_dir, f)) + SUB_CHUNK - 1) // SUB_CHUNK
gdb.write(f"[restore] Loading {total_size} bytes in {len(chunks)} files, {total_sub} sub-chunks of {SUB_CHUNK//1024}KB each\n")

t_global = time.time()
sub_idx = 0
for i, fname in enumerate(chunks):
    fpath = os.path.join(chunk_dir, fname)
    fsize = os.path.getsize(fpath)
    file_base = base_addr + i * chunk_size  # bias for restore command

    for offset in range(0, fsize, SUB_CHUNK):
        sub_end = min(offset + SUB_CHUNK, fsize)
        sub_len = sub_end - offset
        mem_addr = file_base + offset
        sub_idx += 1

        t0 = time.time()
        gdb.execute(f"restore {fpath} binary 0x{file_base:x} 0x{offset:x} 0x{sub_end:x}")
        dt = time.time() - t0

        # Immediately copyback this sub-chunk
        cb_end = (mem_addr + sub_len + 63) & ~63
        run_copyback(mem_addr, cb_end)

        if sub_idx % 4 == 0 or sub_idx == total_sub:
            gdb.write(f"[restore+cb] {sub_idx}/{total_sub}: 0x{mem_addr:08x}+{sub_len//1024}KB  SBA {dt:.1f}s\n")

elapsed_total = time.time() - t_global
gdb.write(f"[ok] fw_payload.bin restored+dirtied in {elapsed_total:.1f}s\n")
end

python
import gdb, os
dtb_default = "/root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux-withinit.dtb"
dtb_path = os.environ.get("DTB_PATH", dtb_default)
gdb.write(f"[dtb] Using: {dtb_path}\n")
gdb.execute(f"restore {dtb_path} binary 0x84000000")

# Copyback DTB immediately (< 4KB = 66 cache lines, trivial)
COPYBACK_ADDR = 0x81200000
dtb_size = os.path.getsize(dtb_path)
dtb_end = (0x84000000 + dtb_size + 63) & ~63
gdb.execute(f"set $a0 = 0x84000000")
gdb.execute(f"set $a1 = 0x{dtb_end:x}")
gdb.execute(f"set $pc = 0x{COPYBACK_ADDR + 4:x}")
gdb.execute(f"hbreak *0x{COPYBACK_ADDR + 0x14:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.write(f"[ok] DTB restored+dirtied at 0x84000000 ({dtb_size} bytes)\n")
end

python
import gdb
linux_w0 = int(gdb.parse_and_eval("*(unsigned int*)0x80200000"))
osbi_w0 = int(gdb.parse_and_eval("*(unsigned int*)0x80000000"))
dtb_magic = int(gdb.parse_and_eval("*(unsigned int*)0x84000000"))
gdb.write(f"[verify] OpenSBI entry: 0x{osbi_w0:08x}\n")
gdb.write(f"[verify] Linux _start: 0x{linux_w0:08x}\n")
gdb.write(f"[verify] DTB magic: 0x{dtb_magic:08x}\n")
end

echo \n=== Phase 2: Boot OpenSBI -> Linux _start ===\n
set $a0 = 0
set $a1 = 0x84000000
set $a2 = 0
set $pc = 0x80000000

delete breakpoints
hbreak *0x8000b1ca
echo [boot] Running OpenSBI to mret...\n
continue

python
import gdb, re
pc = int(gdb.parse_and_eval("$pc"))
if pc != 0x8000b1ca:
    gdb.write(f"[FAIL] Expected mret at 0x8000b1ca, got 0x{pc:x}\n")
    gdb.execute("info reg pc ra sp a0 a1 a2")
    gdb.execute("x/8i $pc")
    raise gdb.GdbError("OpenSBI did not reach mret")
gdb.write("[OK] OpenSBI reached mret at 0x8000b1ca\n")
gdb.execute("delete breakpoints")
gdb.execute("set $a1 = 0x84000000")
out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8})', out)
if m:
    old_dcsr = int(m.group(1), 16)
    new_dcsr = old_dcsr & ~((1 << 15) | (1 << 13) | (1 << 12) | (1 << 2))
    gdb.write(f"[dcsr] old=0x{old_dcsr:08X} -> new=0x{new_dcsr:08X}\n")
    gdb.execute(f"monitor WriteCSR 0x7b0 0x{new_dcsr:08X}")
else:
    gdb.write(f"[dcsr] parse failed: {out.strip()}\n")
gdb.execute("hbreak *0x80200000")
gdb.write("[boot] Continuing from mret to Linux _start...\n")
gdb.execute("continue")
pc2 = int(gdb.parse_and_eval("$pc"))
gdb.write(f"[boot] Stopped at PC = 0x{pc2:x}\n")
if pc2 != 0x80200000:
    gdb.write("[WARN] Did not stop at Linux _start as expected\n")
end

echo \n=== Phase 3: Run kernel for a short window, then halt ===\n
symbol-file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

python
import gdb, time, os, re
run_secs = int(os.environ.get("KERNEL_RUN_SECS", "20"))
run_tag = os.environ.get("RUN_TAG", time.strftime("timedcap_%Y%m%d_%H%M%S"))
die_catch = os.environ.get("DIE_CATCH", "0") == "1"
summary = f"/tmp/{run_tag}_timed_capture.txt"

for trig_idx in range(2):
    gdb.execute(f"monitor WriteCSR 0x7a0 {trig_idx}")
    gdb.execute("monitor WriteCSR 0x7a1 0")
    gdb.execute("monitor WriteCSR 0x7a2 0")
gdb.write("[OK] Hardware triggers cleared\n")

if die_catch:
    # DIE_CATCH mode: set RISC-V debug trigger directly via J-Link WriteCSR
    # Then monitor go + sleep + halt. Trigger fires on die_kernel_fault execute.
    # die_kernel_fault(const char *msg, unsigned long addr, struct pt_regs *regs)
    # a0=msg, a1=badaddr, a2=pt_regs
    gdb.execute("delete breakpoints")
    die_kf_addr = 0xffffffff800089c8
    die_kf_pa = 0x802089c8  # PA = VA - 0xffffffff80000000 + 0x80200000
    
    # Set mcontrol trigger: type=2, dmode=1, s=1, m=1, execute=1, action=1(debug)
    # tdata1 = (2<<60)|(1<<59)|(1<<12)|(1<<6)|(1<<4)|(1<<2) = 0x2800000000001054
    tdata1 = 0x2800000000001054
    gdb.execute("monitor WriteCSR 0x7a0 0")           # tselect = 0
    gdb.execute(f"monitor WriteCSR 0x7a2 0x{die_kf_pa:x}")  # tdata2 = PA of target
    gdb.execute(f"monitor WriteCSR 0x7a1 0x{tdata1:x}")  # tdata1 = mcontrol config
    
    # Verify
    td1_out = gdb.execute("monitor ReadCSR 0x7a1", to_string=True).strip()
    td2_out = gdb.execute("monitor ReadCSR 0x7a2", to_string=True).strip()
    gdb.write(f"[die_catch] trigger set: tdata1={td1_out}, tdata2={td2_out}\n")
    gdb.write(f"[die_catch] die_kernel_fault VA=0x{die_kf_addr:x} PA=0x{die_kf_pa:x}\n")
    
    gdb.execute("monitor go")
    gdb.write("[die_catch] kernel running, waiting 15s for crash...\n")
    import time as _time
    _time.sleep(15)
    gdb.execute("monitor halt")
    _time.sleep(2)
    try:
        gdb.execute("maintenance flush register-cache")
    except gdb.error:
        pass
    
    pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
    gdb.write(f"\n[die_catch] Halted at PC=0x{pc:016x}\n")
    
    at_die_kf = (pc == die_kf_addr or pc == die_kf_pa)
    if at_die_kf:
        gdb.write("[die_catch] *** HIT die_kernel_fault! ***\n")
        # a2 = pt_regs pointer (3rd argument)
        pt = int(gdb.parse_and_eval("$a2")) & 0xFFFFFFFFFFFFFFFF
        msg_ptr = int(gdb.parse_and_eval("$a0")) & 0xFFFFFFFFFFFFFFFF
        fault_addr = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
        gdb.write(f"[die_catch] pt_regs=0x{pt:016x} badaddr=0x{fault_addr:016x}\n")
        try:
            gdb.write(f"[die_catch] msg: {gdb.execute(f'x/s 0x{msg_ptr:x}', to_string=True).strip()}\n")
        except:
            pass
    
    # Read all pt_regs
    regs_def = [
        (0,"epc"),(8,"ra"),(16,"sp"),(24,"gp"),(32,"tp"),
        (40,"t0"),(48,"t1"),(56,"t2"),(64,"s0"),(72,"s1"),
        (80,"a0"),(88,"a1"),(96,"a2"),(104,"a3"),(112,"a4"),(120,"a5"),
        (128,"a6"),(136,"a7"),(144,"s2"),(152,"s3"),(160,"s4"),(168,"s5"),
        (176,"s6"),(184,"s7"),(192,"s8"),(200,"s9"),(208,"s10"),(216,"s11"),
        (224,"t3"),(232,"t4"),(240,"t5"),(248,"t6"),
        (256,"status"),(264,"badaddr"),(272,"cause"),(280,"orig_a0"),
    ]
    
    if at_die_kf:
        gdb.write("\n====== CLEAN pt_regs (from die_kernel_fault a2) ======\n")
        crash_regs = {}
        for off, name in regs_def:
            try:
                val = int(gdb.parse_and_eval(f"*(unsigned long*)({pt:#x}+{off})")) & 0xFFFFFFFFFFFFFFFF
                crash_regs[name] = val
                gdb.write(f"  {name:8s} = 0x{val:016x}\n")
            except Exception as e:
                gdb.write(f"  {name:8s} = ERROR: {e}\n")
        
        epc = crash_regs.get("epc", 0)
        badaddr = crash_regs.get("badaddr", 0)
        cause = crash_regs.get("cause", 0)
        t2 = crash_regs.get("t2", 0)
        a0_c = crash_regs.get("a0", 0)
        s1_c = crash_regs.get("s1", 0)
        
        is_int = (cause >> 63) & 1
        code = cause & 0x7FFFFFFFFFFFFFFF
        gdb.write(f"\n[crash] EPC=0x{epc:x} cause={'int' if is_int else 'exc'} code={code} badaddr=0x{badaddr:x}\n")
        gdb.write(f"[crash] t2=0x{t2:x} a0=0x{a0_c:x} s1=0x{s1_c:x}\n")
        
        try:
            gdb.write(f"\n[disasm]:\n")
            gdb.execute(f"info symbol 0x{epc:x}")
            gdb.execute(f"x/4i 0x{epc:x}")
        except: pass
        
        # Read string data
        gdb.write(f"\n[strings]:\n")
        for name, addr in [("a0", a0_c), ("s1", s1_c), ("t2", t2)]:
            if addr > 0xffffffc000000000:
                try:
                    data = b""
                    for i in range(4):
                        v = int(gdb.parse_and_eval(f"*(unsigned long*)(0x{addr+i*8:x})")) & 0xFFFFFFFFFFFFFFFF
                        data += v.to_bytes(8, "little")
                    nul = data.find(b'\x00')
                    s = data[:nul].decode("ascii",errors="replace") if nul>=0 else data[:32].hex()+"[NO NUL]"
                    gdb.write(f"  {name}(0x{addr:x}) = \"{s}\"\n")
                except Exception as e:
                    gdb.write(f"  {name}(0x{addr:x}) ERR: {e}\n")
            else:
                gdb.write(f"  {name} = 0x{addr:x}\n")
        
        # Save to summary file
        with open(summary, "w") as f:
            for name, val in crash_regs.items():
                f.write(f"{name}=0x{val:016x}\n")
    else:
        gdb.write(f"[die_catch] NOT at die_kernel_fault (PC=0x{pc:x}), reading pt_regs from task stack\n")
        # tp = current task_struct; task->stack at offset 16
        # Need VA→PA conversion since CPU may be halted in M-mode (no MMU)
        tp = int(gdb.parse_and_eval("$tp")) & 0xFFFFFFFFFFFFFFFF
        gdb.write(f"[stack] tp (current task_struct) = 0x{tp:016x}\n")
        
        # Convert kernel VA to PA for lowmem (0xffffffd8... range)
        def va2pa(va):
            if va >= 0xffffffd800000000 and va < 0xffffffd900000000:
                return va - 0xffffffd800000000 + 0x80000000
            elif va >= 0xffffffff80000000:
                return va - 0xffffffff80000000 + 0x80200000
            return va  # already PA or unknown mapping
        
        def read_pa_u64(pa):
            # Use SBA via dump/restore to read PA, avoiding MMU
            import tempfile, struct
            tmp = f"/tmp/_gdb_read_{pa:x}.bin"
            gdb.execute(f"dump binary memory {tmp} 0x{pa:x} 0x{pa+8:x}", to_string=True)
            with open(tmp, "rb") as f:
                return struct.unpack("<Q", f.read(8))[0]
        
        try:
            tp_pa = va2pa(tp)
            gdb.write(f"[stack] tp PA = 0x{tp_pa:016x}\n")
            stack_base_va = read_pa_u64(tp_pa + 16)
            gdb.write(f"[stack] task->stack (VA) = 0x{stack_base_va:016x}\n")
            
            # stack_base is in vmalloc space (0xffffffc8...), not simple VA→PA
            # Instead, use task_pt_regs formula: pt_regs at (stack + THREAD_SIZE - 288)
            pt_va = (stack_base_va + 16384 - 288) & 0xFFFFFFFFFFFFFFFF
            gdb.write(f"[stack] pt_regs VA = 0x{pt_va:016x}\n")
            
            # For vmalloc VA, we need to walk the page table
            # satp PPN gives the root page table PA
            satp_out = gdb.execute("monitor ReadCSR 0x180", to_string=True)
            import re as _re
            satp_m = _re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', satp_out)
            satp_val = int(satp_m.group(1), 16) if satp_m else None
            if satp_val:
                satp_ppn = satp_val & 0xFFFFFFFFFFF  # 44-bit PPN
                root_pt_pa = satp_ppn << 12
                gdb.write(f"[mmu] satp PPN=0x{satp_ppn:x} root_pt PA=0x{root_pt_pa:x}\n")
                
                # SV39 page table walk for pt_va
                vpn2 = (pt_va >> 30) & 0x1FF
                vpn1 = (pt_va >> 21) & 0x1FF
                vpn0 = (pt_va >> 12) & 0x1FF
                pg_off = pt_va & 0xFFF
                
                # Level 2 (root)
                pte2 = read_pa_u64(root_pt_pa + vpn2 * 8)
                gdb.write(f"[mmu] L2 PTE[{vpn2}] = 0x{pte2:016x}\n")
                if pte2 & 1:  # valid
                    if pte2 & 0xE:  # leaf (R/W/X set)
                        # 1GB page
                        pt_pa = ((pte2 >> 10) << 30) | (pt_va & 0x3FFFFFFF)
                    else:
                        # pointer to level 1
                        l1_pa = (pte2 >> 10) << 12
                        pte1 = read_pa_u64(l1_pa + vpn1 * 8)
                        gdb.write(f"[mmu] L1 PTE[{vpn1}] = 0x{pte1:016x}\n")
                        if pte1 & 1:
                            if pte1 & 0xE:  # 2MB leaf
                                pt_pa = ((pte1 >> 10) << 21) | (pt_va & 0x1FFFFF)
                            else:
                                l0_pa = (pte1 >> 10) << 12
                                pte0 = read_pa_u64(l0_pa + vpn0 * 8)
                                gdb.write(f"[mmu] L0 PTE[{vpn0}] = 0x{pte0:016x}\n")
                                if pte0 & 1:
                                    pt_pa = ((pte0 >> 10) << 12) | pg_off
                                else:
                                    raise Exception(f"L0 PTE invalid: 0x{pte0:x}")
                        else:
                            raise Exception(f"L1 PTE invalid: 0x{pte1:x}")
                else:
                    raise Exception(f"L2 PTE invalid: 0x{pte2:x}")
                
                gdb.write(f"[mmu] pt_regs PA = 0x{pt_pa:016x}\n")
                
                # Read all 36 pt_regs fields via SBA
                gdb.write("\n====== CLEAN pt_regs (from task stack via SBA) ======\n")
                crash_regs = {}
                for off, name in regs_def:
                    try:
                        val = read_pa_u64(pt_pa + off)
                        crash_regs[name] = val
                        gdb.write(f"  {name:8s} = 0x{val:016x}\n")
                    except Exception as e:
                        gdb.write(f"  {name:8s} = ERROR: {e}\n")
                
                epc = crash_regs.get("epc", 0)
                badaddr = crash_regs.get("badaddr", 0)
                cause = crash_regs.get("cause", 0)
                is_int = (cause >> 63) & 1
                code = cause & 0x7FFFFFFFFFFFFFFF
                gdb.write(f"\n[crash] EPC=0x{epc:x} cause={'int' if is_int else 'exc'} code={code} badaddr=0x{badaddr:x}\n")
                
                with open(summary, "w") as f:
                    for name, val in crash_regs.items():
                        f.write(f"{name}=0x{val:016x}\n")
            else:
                gdb.write("[mmu] Cannot read satp CSR\n")
        except Exception as e:
            gdb.write(f"[stack] Error: {e}\n")
else:
    gdb.execute("monitor go")
    gdb.write(f"[run] Kernel running for {run_secs}s...\n")
    time.sleep(run_secs)
    gdb.write(f"[run] {run_secs}s elapsed, halting target...\n")
    gdb.execute("monitor halt")
    time.sleep(2)
    try:
        gdb.execute("maintenance flush register-cache")
    except gdb.error:
        pass

def read_csr(csr_num):
    out = gdb.execute(f"monitor ReadCSR 0x{csr_num:x}", to_string=True)
    m = re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', out)
    return (int(m.group(1), 16) if m else None, out.strip())

pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF

# Read ALL relevant CSRs - both S-mode and M-mode
csrs = {}
for name, num in [("sepc", 0x141), ("scause", 0x142), ("stval", 0x143),
                  ("satp", 0x180), ("sstatus", 0x100), ("stvec", 0x105),
                  ("mepc", 0x341), ("mcause", 0x342), ("mtval", 0x343),
                  ("mstatus", 0x300), ("mtvec", 0x305), ("medeleg", 0x302),
                  ("mideleg", 0x303), ("dcsr", 0x7b0), ("dpc", 0x7b1)]:
    val, raw = read_csr(num)
    csrs[name] = (val, raw)
    gdb.write(f"[csr] {name:10s} = {raw}\n")

gdb.write(f"\n[stop] PC = 0x{pc:016x}\n")

# Dump all GPRs
gdb.write("\n[regs] All GPRs:\n")
gdb.execute("info reg pc ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6")

# Check medeleg to see which exceptions are delegated
medeleg = csrs["medeleg"][0]
if medeleg is not None:
    gdb.write(f"\n[analysis] medeleg = 0x{medeleg:016x}\n")
    exc_names = {0: "InstrMisalign", 1: "InstrAccess", 2: "IllegalInstr", 3: "Breakpoint",
                 4: "LoadMisalign", 5: "LoadAccess", 6: "StoreMisalign", 7: "StoreAccess",
                 8: "UEcall", 9: "SEcall", 12: "InstrPageFault", 13: "LoadPageFault",
                 15: "StorePageFault"}
    for bit in range(16):
        delegated = "delegated" if (medeleg >> bit) & 1 else "NOT delegated"
        name = exc_names.get(bit, f"exc{bit}")
        gdb.write(f"  [{bit:2d}] {name:20s} : {delegated}\n")

# Interpret scause and mcause
for prefix in ["s", "m"]:
    cause_name = f"{prefix}cause"
    cause_val = csrs[cause_name][0]
    if cause_val is not None:
        is_interrupt = (cause_val >> 63) & 1
        code = cause_val & 0x7FFFFFFFFFFFFFFF
        kind = "interrupt" if is_interrupt else "exception"
        gdb.write(f"\n[{cause_name}] = {kind} code={code}\n")

# Save summary
with open(summary, "w") as f:
    f.write(f"pc=0x{pc:016x}\n")
    for name, (val, raw) in csrs.items():
        f.write(f"{name}={raw}\n")
gdb.write(f"\n[files] Summary: {summary}\n")

# Disassemble at PC and sepc
try:
    gdb.execute("info symbol $pc")
    gdb.execute("x/8i $pc")
except gdb.error as err:
    gdb.write(f"[pc] symbol/disasm unavailable: {err}\n")

sepc = csrs["sepc"][0]
if sepc is not None:
    try:
        gdb.write(f"\n[fault] Disassembly at sepc=0x{sepc:016x}\n")
        gdb.execute(f"info symbol 0x{sepc:x}")
        gdb.execute(f"x/8i 0x{sepc:x}")
    except gdb.error as err:
        gdb.write(f"[fault] Could not inspect sepc: {err}\n")

mepc = csrs["mepc"][0]
if mepc is not None and mepc != 0:
    try:
        gdb.write(f"\n[trap] Disassembly at mepc=0x{mepc:016x}\n")
        gdb.execute(f"x/8i 0x{mepc:x}")
    except gdb.error as err:
        gdb.write(f"[trap] Could not inspect mepc: {err}\n")

try:
    gdb.execute("bt 30")
except gdb.error as err:
    gdb.write(f"[bt] unavailable: {err}\n")

# Dump klog region: 128KB from __log_buf area
klog_file = f"/tmp/{run_tag}_klog.bin"
gdb.write(f"\n[klog] Dumping klog to {klog_file}\n")
try:
    gdb.execute(f"dump binary memory {klog_file} 0x810D0000 0x81100000")
    gdb.write(f"[klog] Dumped 0x810D0000 - 0x81100000 (192KB around __log_buf PA 0x810D0060)\n")
except gdb.error as err:
    gdb.write(f"[klog] dump error: {err}\n")

# === strlen crash analysis: read memory directly via GDB (no printk corruption) ===
gdb.write("\n=== Post-halt Memory Analysis (GDB-direct, not printk) ===\n")

# Read oops_count to confirm crash happened
try:
    oops = int(gdb.parse_and_eval("*(unsigned int*)&oops_count")) & 0xFFFFFFFF
    gdb.write(f"[oops] oops_count = {oops}\n")
except Exception as e:
    gdb.write(f"[oops] Cannot read oops_count: {e}\n")

# Read saved_command_line - pointer lives in kernel BSS
try:
    # Get the pointer from physical memory (VA→PA: PA = VA + 0x100200000 mod 2^64)
    ptr_va = int(gdb.parse_and_eval("(unsigned long)&saved_command_line")) & 0xFFFFFFFFFFFFFFFF
    gdb.write(f"[cmdline] saved_command_line variable at VA 0x{ptr_va:016x}\n")
    # Use kernel VA since MMU/satp is still set from the crashed kernel
    ptr = int(gdb.parse_and_eval("*(unsigned long*)&saved_command_line")) & 0xFFFFFFFFFFFFFFFF
    gdb.write(f"[cmdline] saved_command_line pointer = 0x{ptr:016x}\n")
    if ptr != 0 and ptr > 0xffffffc000000000:
        data = b""
        for i in range(32):
            val = int(gdb.parse_and_eval(f"*(unsigned long*)0x{ptr + i*8:x}")) & 0xFFFFFFFFFFFFFFFF
            data += val.to_bytes(8, "little")
        nul_pos = data.find(b'\x00')
        if nul_pos >= 0:
            cmdline = data[:nul_pos].decode("ascii", errors="replace")
        else:
            cmdline = data[:256].decode("ascii", errors="replace")
            cmdline += " [NO NUL IN 256 BYTES!]"
        gdb.write(f"[cmdline] = \"{cmdline}\"\n")
except Exception as e:
    gdb.write(f"[cmdline] Cannot read: {e}\n")

# Check kernel log_buf for clean text
# log_buf is initially __log_buf but may be reallocated
try:
    log_buf_va = int(gdb.parse_and_eval("*(unsigned long*)&log_buf")) & 0xFFFFFFFFFFFFFFFF
    log_buf_len = int(gdb.parse_and_eval("*(unsigned int*)&log_buf_len")) & 0xFFFFFFFF
    gdb.write(f"[log_buf] VA = 0x{log_buf_va:016x}, len = {log_buf_len}\n")
except Exception as e:
    gdb.write(f"[log_buf] Cannot read: {e}\n")

# If the kernel was halted in panic idle (not in strlen itself),
# read the stack at the crash point using physical addresses
# The s-registers (callee-saved) should be preserved from the crash context
gdb.write("\n[s-regs] Callee-saved registers (may reflect crash context):\n")
for rname in ["s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11"]:
    try:
        val = int(gdb.parse_and_eval(f"${rname}")) & 0xFFFFFFFFFFFFFFFF
        gdb.write(f"  {rname:4s} = 0x{val:016x}\n")
    except:
        pass

# Try to read memory around the string pointer in s1/s9 (parameq saves input)
gdb.write("\n[mem] Reading string data around s-register pointers:\n")
for rname in ["s1", "s9"]:
    try:
        addr = int(gdb.parse_and_eval(f"${rname}")) & 0xFFFFFFFFFFFFFFFF
        if addr > 0xffffffc000000000:
            data = b""
            for i in range(8):
                val = int(gdb.parse_and_eval(f"*(unsigned long*)0x{addr - 8 + i*8:x}")) & 0xFFFFFFFFFFFFFFFF
                data += val.to_bytes(8, "little")
            gdb.write(f"  {rname} = 0x{addr:016x}: {data.hex()}\n")
            # Show as string if possible
            printable = ""
            for b in data:
                if 32 <= b < 127:
                    printable += chr(b)
                elif b == 0:
                    printable += "\\0"
                else:
                    printable += f"\\x{b:02x}"
            gdb.write(f"         ascii: {printable}\n")
    except Exception as e:
        gdb.write(f"  {rname}: Cannot read: {e}\n")

gdb.write("\n[analysis] strlen crash diagnosis complete\n")
end

quit
