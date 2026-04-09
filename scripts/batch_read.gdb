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
gdb.write(f"[state] PC=0x{pc:x}\n")

# Read all CSRs
gdb.write("\n=== CSRs ===\n")
for name, num in [("sepc", 0x141), ("scause", 0x142), ("stval", 0x143),
                  ("satp", 0x180), ("sstatus", 0x100), ("stvec", 0x105),
                  ("mepc", 0x341), ("mcause", 0x342), ("mtval", 0x343),
                  ("mstatus", 0x300), ("mtvec", 0x305), ("medeleg", 0x302),
                  ("mscratch", 0x340), ("sscratch", 0x140)]:
    out = gdb.execute(f"monitor ReadCSR 0x{num:x}", to_string=True).strip()
    gdb.write(f"  {name:10s} = {out}\n")

gdb.write("\n=== All GPRs ===\n")
gdb.execute("info reg")

# --- Batch reader: write a loop routine that reads N words from VA array ---
# and stores results to a PA buffer, then ebreak.
# This avoids fence.i + hbreak + continue per read.

ROUTINE = 0x80038000
INBUF   = 0x80038100  # input: array of VAs to read (each 8 bytes)
OUTBUF  = 0x80038200  # output: results stored here (each 8 bytes)

# Routine (at ROUTINE):
#   fence.i           ; a0 = count, a1 = inbuf, a2 = outbuf
#   loop: ld t0, 0(a1)      ; t0 = VA to read
#         ld t1, 0(t0)      ; t1 = *VA (uses MPRV S-mode translation!)
#         sd t1, 0(a2)      ; store result (M-mode, PA, no translation)
#         addi a1, a1, 8
#         addi a2, a2, 8
#         addi a0, a0, -1
#         bnez a0, loop
#   ebreak

# But WAIT: with MPRV=1, BOTH ld AND sd use S-mode translation!
# So sd t1, 0(a2) also translates a2 through S-mode page table.
# We need a2 to be a VIRTUAL address that maps to a known PA.
# The direct mapping VA 0xffffffd800000000 + (PA - 0x80000000) should work.
# So OUTBUF PA 0x80038200 → direct map VA = 0xffffffd800038200

# Actually, let's avoid the complexity. Just read ONE word at a time using
# a fast ld+ebreak pattern, but avoid fence.i on each call.

# Write the routine ONCE:
code = [
    0x0000100f,  # fence.i
    0x00053583,  # ld a1, 0(a0)     ; a1 = *(a0), a0 = VA
    0x00100073,  # ebreak
]
for i, insn in enumerate(code):
    gdb.execute(f"set *(unsigned int*)0x{ROUTINE + i*4:x} = 0x{insn:08x}")

# Read mstatus and set MPRV=1 MPP=S
mstatus_out = gdb.execute("monitor ReadCSR 0x300", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', mstatus_out)
mstatus = int(m.group(1), 16) if m else 0
new_mstatus = mstatus | (1 << 17)  # MPRV=1
new_mstatus = (new_mstatus & ~(3 << 11)) | (1 << 11)  # MPP=S

# Execute fence.i ONCE to flush I-cache for the routine
gdb.execute(f"monitor WriteCSR 0x300 0x{new_mstatus:x}")
gdb.execute(f"set $a0 = 0x{ROUTINE:x}")  # dummy addr (read routine itself)
gdb.execute(f"set $pc = 0x{ROUTINE:x}")
gdb.execute(f"hbreak *0x{ROUTINE + 8:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.execute(f"monitor WriteCSR 0x300 0x{new_mstatus:x}")
gdb.write("[init] Reader routine installed and tested\n")

def read_val(va):
    gdb.execute(f"set $a0 = 0x{va:x}")
    gdb.execute(f"set $pc = 0x{ROUTINE + 4:x}")  # skip fence.i (already cached)
    gdb.execute(f"hbreak *0x{ROUTINE + 8:x}")
    gdb.execute("continue")
    val = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
    gdb.execute("delete breakpoints")
    gdb.execute(f"monitor WriteCSR 0x300 0x{new_mstatus:x}")
    return val

# Read key kernel symbols
gdb.write("\n=== Kernel variables (via CPU MPRV ld) ===\n")

reads = [
    # printk-related
    ("log_buf", 0xffffffff80cbf368),
    ("log_buf_len", 0xffffffff80cbf360),
    ("__log_buf_w0", 0xffffffff80cd0060),
    ("__log_buf_w1", 0xffffffff80cd0068),
    ("__log_buf_w2", 0xffffffff80cd0070),
    ("__log_buf_w3", 0xffffffff80cd0078),
    # boot state
    ("saved_command_line", 0xffffffff80918468),
    ("oops_count", 0xffffffff80cc0240),
    # Process state  
    ("init_task.comm[0:8]", 0xffffffff80c06af0),  # approx, needs verification
]

# Get actual init_task address
import subprocess
p = subprocess.run(["/opt/conda/envs/firemarshal/riscv-tools/bin/riscv64-unknown-linux-gnu-nm",
                    "/root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux"],
                   capture_output=True, text=True)
for line in p.stdout.split('\n'):
    parts = line.split()
    if len(parts) >= 3 and parts[2] == 'init_task':
        init_task_va = int(parts[0], 16)
        gdb.write(f"[sym] init_task @ 0x{init_task_va:x}\n")
        # task_struct.comm is at offset 0x358 (approx for 6.6.0)
        reads.append(("init_task.state", init_task_va))
        reads.append(("init_task+8", init_task_va + 8))
        break
    if len(parts) >= 3 and parts[2] == 'jiffies_64':
        jiffies_va = int(parts[0], 16)
        reads.append(("jiffies_64", jiffies_va))
        gdb.write(f"[sym] jiffies_64 @ 0x{jiffies_va:x}\n")
    if len(parts) >= 3 and parts[2] == 'system_state':
        sys_state_va = int(parts[0], 16)
        reads.append(("system_state", sys_state_va))
        gdb.write(f"[sym] system_state @ 0x{sys_state_va:x}\n")

for name, va in reads:
    try:
        val = read_val(va)
        # Also show as ASCII if it looks like text
        asc = ""
        bval = val.to_bytes(8, "little")
        for b in bval:
            if 32 <= b < 127:
                asc += chr(b)
            elif b == 0:
                asc += "\\0"
            else:
                asc += "."
        gdb.write(f"  {name:25s} = 0x{val:016x}  [{asc}]\n")
    except Exception as e:
        gdb.write(f"  {name:25s} = ERROR: {e}\n")

# Read more __log_buf data (printk record buffer)
gdb.write("\n=== First 128 bytes of __log_buf ===\n")
data = b""
for off in range(0, 128, 8):
    try:
        w = read_val(0xffffffff80cd0060 + off)
        data += w.to_bytes(8, "little")
    except:
        break
# Print hex+ascii
for i in range(0, len(data), 16):
    chunk = data[i:i+16]
    hex_str = " ".join(f"{b:02x}" for b in chunk)
    asc_str = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
    gdb.write(f"  {i:04x}: {hex_str:48s} {asc_str}\n")

# Restore mstatus
gdb.execute(f"monitor WriteCSR 0x300 0x{mstatus:x}")
gdb.write("\n[done]\n")
end

quit
