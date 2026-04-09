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

# Save state
pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
save_a0 = int(gdb.parse_and_eval("$a0")) & 0xFFFFFFFFFFFFFFFF
save_a1 = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"[state] PC=0x{pc:x}\n")

# Read CSRs for current state
for name, num in [("sepc", 0x141), ("scause", 0x142), ("stval", 0x143),
                  ("mepc", 0x341), ("mcause", 0x342), ("mtval", 0x343),
                  ("satp", 0x180), ("mstatus", 0x300)]:
    out = gdb.execute(f"monitor ReadCSR 0x{num:x}", to_string=True).strip()
    gdb.write(f"[csr] {name:10s} = {out}\n")

mstatus_out = gdb.execute("monitor ReadCSR 0x300", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', mstatus_out)
mstatus = int(m.group(1), 16) if m else 0

# Set MPRV=1 MPP=S for reading via S-mode translation
new_mstatus = mstatus | (1 << 17)  # MPRV
new_mstatus = (new_mstatus & ~(3 << 11)) | (1 << 11)  # MPP=S

READER = 0x80038000
instrs = [0x0000100f, 0x00053583, 0x00100073]  # fence.i, ld a1, 0(a0), ebreak
for i, insn in enumerate(instrs):
    gdb.execute(f"set *(unsigned int*)0x{READER + i*4:x} = 0x{insn:08x}")
gdb.execute(f"monitor WriteCSR 0x300 0x{new_mstatus:x}")

def read_kernel_u64(va):
    gdb.execute(f"set $a0 = 0x{va:x}")
    gdb.execute(f"set $pc = 0x{READER:x}")
    gdb.execute(f"hbreak *0x{READER + 8:x}")
    gdb.execute("continue")
    val = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
    gdb.execute("delete breakpoints")
    gdb.execute(f"monitor WriteCSR 0x300 0x{new_mstatus:x}")
    return val

def read_kernel_u32(va):
    return read_kernel_u64(va) & 0xFFFFFFFF

# Read the actual instructions at mepc and surrounding area via MMU
# mepc/sepc from the boot log were 0xffffffff8045176c / 0xffffffff80451770
# These are the ACTUAL instructions in L2 cache (not the stale DDR values)

gdb.write(f"\n=== Reading actual code via MMU (what the CPU sees) ===\n")

# Read 64 bytes (16 instructions) around 0xffffffff80451760
gdb.write(f"Instructions at 0xffffffff80451760 - 0xffffffff80451790:\n")
for addr in range(0xffffffff80451760, 0xffffffff804517a0, 4):
    try:
        insn = read_kernel_u32(addr)
        gdb.write(f"  0x{addr:x}: 0x{insn:08x}\n")
    except Exception as e:
        gdb.write(f"  0x{addr:x}: ERROR {e}\n")
        break

# Also check what's at the start of this code region (0xffffffff80451700)
gdb.write(f"\nInstructions at 0xffffffff80451700 - 0xffffffff80451740:\n")
for addr in range(0xffffffff80451700, 0xffffffff80451740, 4):
    try:
        insn = read_kernel_u32(addr)
        gdb.write(f"  0x{addr:x}: 0x{insn:08x}\n")
    except Exception as e:
        gdb.write(f"  0x{addr:x}: ERROR {e}\n")
        break

# Check some early kernel symbols to see how far boot progressed
# start_kernel at some VA... let me read a known early variable
# init_task is at a fixed location
gdb.write(f"\n=== Boot progress indicators ===\n")

# Read jiffies_64 (tells us how many timer ticks)
try:
    # Need to find actual jiffies_64 address
    # For now, check if early boot variables are set
    pass
except:
    pass

# Check: is the kernel at the cpu_idle loop?
# WFI instruction encoding: 0x10500073
gdb.write(f"\n=== Checking for WFI patterns ===\n")
for addr in range(0xffffffff80451760, 0xffffffff80451790, 4):
    try:
        insn = read_kernel_u32(addr)
        if insn == 0x10500073:
            gdb.write(f"  WFI found at 0x{addr:x}!\n")
    except:
        break

# Resume the kernel and let it run for 30s, then halt again
# to see if sepc changed (progress indicator)
gdb.write(f"\n=== Sampling sepc to check if kernel is making progress ===\n")
gdb.execute(f"set $a0 = 0x{save_a0:x}")
gdb.execute(f"set $a1 = 0x{save_a1:x}")
gdb.execute(f"set $pc = 0x{pc:x}")
gdb.execute(f"monitor WriteCSR 0x300 0x{mstatus:x}")

samples = []
for i in range(5):
    gdb.execute("monitor go")
    time.sleep(10)
    gdb.execute("monitor halt")
    time.sleep(1)
    try:
        gdb.execute("maintenance flush register-cache")
    except:
        pass
    
    cur_pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
    sepc_out = gdb.execute("monitor ReadCSR 0x141", to_string=True).strip()
    m2 = re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', sepc_out)
    sepc = int(m2.group(1), 16) if m2 else 0
    
    mcause_out = gdb.execute("monitor ReadCSR 0x342", to_string=True).strip()
    m3 = re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', mcause_out)
    mcause = int(m3.group(1), 16) if m3 else 0
    
    mepc_out = gdb.execute("monitor ReadCSR 0x341", to_string=True).strip()
    m4 = re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', mepc_out)
    mepc = int(m4.group(1), 16) if m4 else 0
    
    samples.append((cur_pc, sepc, mepc, mcause))
    gdb.write(f"[sample {i}] PC=0x{cur_pc:x} sepc=0x{sepc:x} mepc=0x{mepc:x} mcause=0x{mcause:x}\n")

# Analyze: are sepc samples the same or different?
sepc_set = set(s[1] for s in samples)
mepc_set = set(s[2] for s in samples)
if len(sepc_set) == 1:
    gdb.write(f"\n[analysis] sepc is CONSTANT (0x{list(sepc_set)[0]:x}) - kernel may be STUCK!\n")
else:
    gdb.write(f"\n[analysis] sepc varies ({len(sepc_set)} unique values) - kernel is making progress\n")
    for v in sorted(sepc_set):
        gdb.write(f"  sepc = 0x{v:x}\n")

gdb.write("\n[done]\n")
end

quit
