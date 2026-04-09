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

# Save all registers
saved_regs = {}
for r in ["pc", "ra", "sp", "gp", "tp", "a0", "a1", "a2", "a3", "a4", "a5", "t0", "t1"]:
    saved_regs[r] = int(gdb.parse_and_eval(f"${r}")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"[save] Saved {len(saved_regs)} registers, PC=0x{saved_regs['pc']:x}\n")

# Read mstatus to see MPRV, MPP
mstatus_out = gdb.execute("monitor ReadCSR 0x300", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', mstatus_out)
mstatus = int(m.group(1), 16) if m else 0
gdb.write(f"[mstatus] = 0x{mstatus:016x}\n")
mprv = (mstatus >> 17) & 1
mpp = (mstatus >> 11) & 3
gdb.write(f"[mstatus] MPRV={mprv} MPP={mpp}\n")

# Strategy: Write a routine at COPYBACK_ADDR that:
# 1. Sets MPRV=1 and MPP=1 (S-mode) in mstatus so loads use S-mode translation
# 2. Reads 8 bytes from address in a0 using ld
# 3. Stores result in a1 (register), hits ebreak
#
# Or simpler: just enable MPRV+MPP=S in mstatus, then use GDB to read memory.
# When MPRV=1 and MPP=S, loads/stores in M-mode use S-mode address translation.

# Set MPRV=1 and MPP=01 (S-mode) in mstatus
# MPP is at bits [12:11], MPRV is bit 17
new_mstatus = mstatus | (1 << 17)  # MPRV = 1
new_mstatus = (new_mstatus & ~(3 << 11)) | (1 << 11)  # MPP = 01 (S-mode)
gdb.write(f"[mstatus] Setting MPRV=1 MPP=S: 0x{new_mstatus:016x}\n")
gdb.execute(f"monitor WriteCSR 0x300 0x{new_mstatus:x}")

# Also set satp to the kernel's page table
satp_out = gdb.execute("monitor ReadCSR 0x180", to_string=True)
gdb.write(f"[satp] = {satp_out.strip()}\n")

# Now, write a small "reader" routine that reads memory via ld (through MMU)
# and stores the result to a fixed PA, then hits ebreak
READER_ADDR = 0x81200000
# a0 = source VA to read
# a1 = count of 8-byte words to read
# a2 = destination PA for storing results
# Loop: ld t0, (a0); sd t0, (a2); addi a0, 8; addi a2, 8; addi a1, -1; bnez a1, loop; ebreak

# But we need MPRV to be set for ld to use S-mode translation...
# Actually, the CPU is halted. GDB memory reads use abstract access or SBA.
# Let me try a different approach: write and execute a routine.

# Routine at READER_ADDR:
#   csrr t0, mstatus        # save mstatus
#   li t1, (1<<17)
#   or t0, t0, t1           # set MPRV
#   csrw mstatus, t0
#   ld t0, 0(a0)            # load via S-mode translation
#   sd t0, 0(a2)            # store result (using M-mode = PA since we store to PA)
# But wait, with MPRV=1, ALL loads AND stores use MPP translation mode.
# So sd would also use S-mode translation. We need a PA destination that maps in S-mode too.
# Actually, the direct mapping (0xffffffd800000000) maps all of physical RAM.
# Use a direct-mapping VA as the destination.

# Simpler approach: write a routine that reads N word from src(a0) to dst(a2),
# src is kernel VA (uses S-mode translation via MPRV), dst is ALSO a VA in direct map.
# But then the SBA read of the destination would have the same problem...

# Actually the SIMPLEST approach:
# 1. Execute a read loop: ld t0, 0(a0); sd t0, 0(a2); add a0, 8; add a2, 8; blt a2, a3, -16; ebreak
# 2. Store to a PA range (with MPRV=0 for stores, MPRV=1 for loads)
# 3. But MPRV affects both ld and sd equally...

# Let me reconsider. When MPRV=1, both loads and stores use MPP privelege.
# So we can't mix VA loads with PA stores.

# Alternative: Read via ld to register, then manually extract via GDB "info reg"
# This is slow but works: one word at a time.

# Write a simple routine: ld a1, 0(a0); ebreak
# Execute it, read a1, repeat for each address.
instrs = [
    (READER_ADDR + 0x00, 0x0000100f),  # fence.i
    (READER_ADDR + 0x04, 0x00053583),  # ld a1, 0(a0)  -- a1 = *(a0)
    (READER_ADDR + 0x08, 0x00100073),  # ebreak
]
for addr, val in instrs:
    gdb.execute(f"set *(unsigned int*)0x{addr:x} = 0x{val:08x}")

# Copyback the routine
gdb.execute(f"set $a0 = 0x{READER_ADDR:x}")
gdb.execute(f"set $a1 = 0x{READER_ADDR + 64:x}")
gdb.execute(f"set $pc = 0x{READER_ADDR:x}")  # fence.i + ld a1, 0(a0) (reads from READER_ADDR itself)
gdb.execute(f"hbreak *0x{READER_ADDR + 0x08:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")

# Now we need MPRV=1 MPP=S so ld uses S-mode (kernel) address translation
gdb.execute(f"monitor WriteCSR 0x300 0x{new_mstatus:x}")
time.sleep(0.2)

def read_va_word(va):
    """Read one 8-byte word from a kernel VA using the CPU's ld instruction"""
    gdb.execute(f"set $a0 = 0x{va:x}")
    gdb.execute(f"set $pc = 0x{READER_ADDR + 0x04:x}")  # skip fence.i
    gdb.execute(f"hbreak *0x{READER_ADDR + 0x08:x}")
    gdb.execute("continue")
    val = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
    gdb.execute("delete breakpoints")
    # Restore MPRV after each read (ebreak clears it?)
    gdb.execute(f"monitor WriteCSR 0x300 0x{new_mstatus:x}")
    return val

# Read key kernel variables via CPU ld (through MMU!)
gdb.write("\n=== Reading kernel variables via CPU ld (through MMU) ===\n")

vars_to_read = [
    ("log_buf", 0xffffffff80cbf368),
    ("log_buf_len", 0xffffffff80cbf370),
    ("__log_buf[0:8]", 0xffffffff80cd0060),
    ("saved_command_line", 0xffffffff80918468),
    ("oops_count", 0xffffffff80cc0240),
]

results = {}
for name, va in vars_to_read:
    try:
        val = read_va_word(va)
        results[name] = val
        gdb.write(f"[cpu_rd] {name:25s} @ 0x{va:x} = 0x{val:016x}\n")
    except Exception as e:
        gdb.write(f"[cpu_rd] {name:25s} ERROR: {e}\n")

# If log_buf is valid, try to read some from it
log_buf = results.get("log_buf", 0)
log_buf_len_val = results.get("log_buf_len", 0) & 0xFFFFFFFF
gdb.write(f"\n[klog] log_buf = 0x{log_buf:016x}, len = {log_buf_len_val}\n")

if log_buf > 0xffffffc000000000 and log_buf_len_val > 0:
    # Read first 1KB of log buffer
    gdb.write("[klog] Reading first 1KB of log buffer...\n")
    data = b""
    read_size = min(log_buf_len_val, 1024)
    for off in range(0, read_size, 8):
        try:
            word = read_va_word(log_buf + off)
            data += word.to_bytes(8, "little")
        except:
            break
    gdb.write(f"[klog] Read {len(data)} bytes\n")
    # Find printk records - they contain text after a header
    # Just dump as text
    text = ""
    for b in data:
        if 32 <= b < 127 or b == 10:
            text += chr(b)
        elif b == 0:
            text += ""
        else:
            text += f"."
    gdb.write(f"[klog] text:\n{text[:2000]}\n")
elif log_buf == 0:
    # log_buf not set, try __log_buf
    gdb.write("[klog] log_buf=NULL, reading __log_buf...\n")
    data = b""
    for off in range(0, 512, 8):
        try:
            word = read_va_word(0xffffffff80cd0060 + off)
            data += word.to_bytes(8, "little")
        except:
            break
    text = ""
    for b in data:
        if 32 <= b < 127 or b == 10:
            text += chr(b)
        elif b == 0:
            text += ""
        else:
            text += "."
    if text.strip():
        gdb.write(f"[klog] __log_buf text:\n{text[:1000]}\n")
    else:
        gdb.write("[klog] __log_buf is empty/zeros\n")

# If saved_command_line points somewhere valid, read the string
scl = results.get("saved_command_line", 0)
if scl > 0xffffffc000000000:
    gdb.write(f"\n[cmdline] Reading string at 0x{scl:x}...\n")
    data = b""
    for off in range(0, 256, 8):
        try:
            word = read_va_word(scl + off)
            data += word.to_bytes(8, "little")
        except:
            break
    nul = data.find(b'\x00')
    s = data[:nul].decode("ascii", errors="replace") if nul >= 0 else data.hex()
    gdb.write(f"[cmdline] = \"{s}\"\n")

# Restore registers
gdb.write("\n[restore] Restoring saved registers...\n")
for r, v in saved_regs.items():
    gdb.execute(f"set ${r} = 0x{v:x}")
# Restore original mstatus
gdb.execute(f"monitor WriteCSR 0x300 0x{mstatus:x}")
gdb.write("[restore] Done\n")

end

quit
