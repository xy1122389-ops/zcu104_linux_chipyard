## strlen_debug.gdb — Boot kernel then break on strlen crash to get clean registers
## Usage: JLINK_PORT=12331 riscv64-unknown-linux-gnu-gdb -x scripts/strlen_debug.gdb

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

## ===== Phase 1: Load payload (same as main script) =====
echo \n=== Phase 1: Restore fw_payload.bin ===\n

python
import gdb, os, time, glob

chunk_dir = "/tmp/fw_chunks_allpatch"
dtb_path = "/root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux-withinit.dtb"
COPYBACK_ADDR = 0x81200000
SENTINEL_ADDR = 0x81200014
CHUNK_SIZE = 256 * 1024

# Write copyback routine
cb_code = bytes([
    0x73, 0x00, 0x50, 0x10,  # wfi
    0x83, 0x32, 0x05, 0x00,  # ld t0, 0(a0)
    0x23, 0x30, 0x55, 0x00,  # sd t0, 0(a0)
    0x13, 0x05, 0x85, 0x00,  # addi a0, a0, 8
    0xe3, 0x4c, 0xb5, 0xfe,  # blt a0, a1, -8
    0x23, 0xb0, 0x05, 0x00,  # sd zero, 0(a1)
    0x6f, 0xf0, 0x5f, 0xfe,  # j COPYBACK_ADDR (wfi)
])
import tempfile
with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as f:
    f.write(cb_code)
    tmp_cb = f.name
gdb.execute(f"restore {tmp_cb} binary {COPYBACK_ADDR:#x}")
os.unlink(tmp_cb)

# Dirty the copyback routine itself
gdb.execute(f"set $pc = {COPYBACK_ADDR:#x}")
gdb.execute(f"set $a0 = {COPYBACK_ADDR:#x}")
gdb.execute(f"set $a1 = {COPYBACK_ADDR + len(cb_code):#x}")
gdb.execute(f"hbreak *{SENTINEL_ADDR:#x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.write("[copyback] Routine at 0x81200000 written and dirtied\n")

# Get sorted chunk files
files = sorted(glob.glob(os.path.join(chunk_dir, "chunk_*.bin")))
total_size = sum(os.path.getsize(f) for f in files)
n_subchunks = (total_size + CHUNK_SIZE - 1) // CHUNK_SIZE
gdb.write(f"[restore] Loading {total_size} bytes in {len(files)} files, {n_subchunks} sub-chunks of {CHUNK_SIZE//1024}KB each\n")

base_addr = 0x80000000
sub_idx = 0
t0 = time.time()
for fpath in files:
    fsize = os.path.getsize(fpath)
    offset = 0
    while offset < fsize:
        end = min(offset + CHUNK_SIZE, fsize)
        addr = base_addr + offset
        gdb.execute(f"restore {fpath} binary {addr - offset:#x} {offset} {end}")
        # copyback
        gdb.execute(f"set $pc = {COPYBACK_ADDR + 4:#x}")
        gdb.execute(f"set $a0 = {addr:#x}")
        gdb.execute(f"set $a1 = {addr + (end - offset):#x}")
        gdb.execute(f"set *((unsigned long*){SENTINEL_ADDR:#x}) = 1")
        gdb.execute(f"hbreak *{SENTINEL_ADDR:#x}")
        gdb.execute("continue")
        gdb.execute("delete breakpoints")
        sub_idx += 1
        elapsed = time.time() - t0
        kb = (end - offset) // 1024
        gdb.write(f"[restore+cb] {sub_idx}/{n_subchunks}: {addr:#x}+{kb}KB  SBA {elapsed:.1f}s\n")
        offset = end
    base_addr += fsize

elapsed = time.time() - t0
gdb.write(f"[ok] fw_payload.bin restored+dirtied in {elapsed:.1f}s\n")

# Load DTB
gdb.write(f"[dtb] Using: {dtb_path}\n")
gdb.execute(f"restore {dtb_path} binary 0x84000000")
gdb.execute(f"set $pc = {COPYBACK_ADDR + 4:#x}")
gdb.execute(f"set $a0 = 0x84000000")
dtb_size = os.path.getsize(dtb_path)
gdb.execute(f"set $a1 = {0x84000000 + dtb_size:#x}")
gdb.execute(f"set *((unsigned long*){SENTINEL_ADDR:#x}) = 1")
gdb.execute(f"hbreak *{SENTINEL_ADDR:#x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.write(f"[ok] DTB restored+dirtied at 0x84000000 ({dtb_size} bytes)\n")
end

## ===== Phase 2: Boot OpenSBI -> Linux _start =====
echo \n=== Phase 2: Boot OpenSBI -> mret -> Linux _start ===\n
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
    raise gdb.GdbError("OpenSBI did not reach mret")
gdb.write("[OK] OpenSBI reached mret\n")
gdb.execute("delete breakpoints")
gdb.execute("set $a1 = 0x84000000")

# Clear DCSR ebreakm/s/u bits
out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8})', out)
if m:
    old_dcsr = int(m.group(1), 16)
    new_dcsr = old_dcsr & ~((1 << 15) | (1 << 13) | (1 << 12) | (1 << 2))
    gdb.write(f"[dcsr] old=0x{old_dcsr:08X} -> new=0x{new_dcsr:08X}\n")
    gdb.execute(f"monitor WriteCSR 0x7b0 0x{new_dcsr:08X}")

gdb.execute("hbreak *0x80200000")
gdb.write("[boot] Continuing from mret to Linux _start...\n")
gdb.execute("continue")
pc2 = int(gdb.parse_and_eval("$pc"))
gdb.write(f"[boot] Stopped at PC = 0x{pc2:x}\n")
end

## ===== Phase 3: Set hbreak on strlen loop load, then run kernel =====
echo \n=== Phase 3: strlen crash diagnosis ===\n
symbol-file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

python
import gdb, time, re

# strlen+0x3c = 0xffffffff80451eb8 = the aligned loop 'ld t3, 0(t2)' that crashed
# Instead of breaking there (too many hits), let's run kernel with a time limit
# then check if it crashed

gdb.execute("delete breakpoints")

# Run the kernel for a while to let it reach the crash point
gdb.write("[run] Starting kernel, waiting 15 seconds for boot to reach crash...\n")
gdb.execute("monitor go")
time.sleep(15)
gdb.execute("monitor halt")
time.sleep(1)
try:
    gdb.execute("maintenance flush register-cache")
except gdb.error:
    pass

# Read scause to see if we have a pending exception
import re
out = gdb.execute("monitor ReadCSR 0x142", to_string=True)  # scause
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', out)
scause = int(m.group(1), 16) if m else 0

out = gdb.execute("monitor ReadCSR 0x141", to_string=True)  # sepc
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', out)
sepc = int(m.group(1), 16) if m else 0

out = gdb.execute("monitor ReadCSR 0x143", to_string=True)  # stval
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', out)
stval = int(m.group(1), 16) if m else 0

pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"\n[halted] PC = 0x{pc:016x}\n")
gdb.write(f"[halted] sepc = 0x{sepc:016x}\n")
gdb.write(f"[halted] scause = 0x{scause:016x}\n")
gdb.write(f"[halted] stval = 0x{stval:016x}\n")

# Dump ALL GPRs via GDB (clean, no printk corruption)
gdb.write("\n[regs] Clean GPR dump from GDB:\n")
for rname in ["pc", "ra", "sp", "gp", "tp",
              "t0", "t1", "t2", "t3", "t4", "t5", "t6",
              "s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11",
              "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7"]:
    try:
        val = int(gdb.parse_and_eval(f"${rname}")) & 0xFFFFFFFFFFFFFFFF
        gdb.write(f"  {rname:4s} = 0x{val:016x}\n")
    except:
        gdb.write(f"  {rname:4s} = <unavailable>\n")

# Try to disassemble around pc and sepc
gdb.write("\n[disasm] At PC:\n")
try:
    gdb.execute(f"info symbol 0x{pc:x}")
    gdb.execute(f"x/8i 0x{pc:x}")
except:
    gdb.write("  <unavailable>\n")

if sepc != 0:
    gdb.write(f"\n[disasm] At sepc (0x{sepc:016x}):\n")
    try:
        gdb.execute(f"info symbol 0x{sepc:x}")
        gdb.execute(f"x/8i 0x{sepc:x}")
    except:
        gdb.write("  <unavailable>\n")

# Now read memory around the string pointer that strlen was processing
# From the oops, s1 = a0 = input string pointer to parameq
# Let's read the kernel command line area and the current stack
gdb.write("\n[mem] Checking kernel cmdline and surrounding data:\n")

# Read the actual value at the addresses around parse_args
# The kernel_init_freeable calls parse_args with the cmd line
# Let's check if the kernel panicked by reading the oops counter
try:
    oops = int(gdb.parse_and_eval("*(unsigned int*)&oops_count")) & 0xFFFFFFFF
    gdb.write(f"  oops_count = {oops}\n")
except:
    gdb.write("  oops_count: <cannot read>\n")

# Read saved_command_line
try:
    ptr = int(gdb.parse_and_eval("(unsigned long)saved_command_line")) & 0xFFFFFFFFFFFFFFFF
    gdb.write(f"  saved_command_line @ 0x{ptr:016x}\n")
    if ptr != 0:
        # Read 256 bytes of the command line
        data = b""
        for i in range(32):
            val = int(gdb.parse_and_eval(f"*(unsigned long*)0x{ptr + i*8:x}")) & 0xFFFFFFFFFFFFFFFF
            data += val.to_bytes(8, "little")
        # Find NUL
        nul_pos = data.find(b'\x00')
        if nul_pos >= 0:
            cmdline = data[:nul_pos].decode("ascii", errors="replace")
        else:
            cmdline = data.decode("ascii", errors="replace")
        gdb.write(f"  cmdline = \"{cmdline}\"\n")
except Exception as e:
    gdb.write(f"  saved_command_line: <cannot read: {e}>\n")

# Try to examine the string at s1 (parameq's input parameter)
gdb.write("\n[mem] Examining string area at registers s1 and a0:\n")
for rname in ["s1", "a0"]:
    try:
        addr = int(gdb.parse_and_eval(f"${rname}")) & 0xFFFFFFFFFFFFFFFF
        if 0xffffffc000000000 <= addr <= 0xffffffffffffffff or 0x80000000 <= addr <= 0xffffffff:
            gdb.write(f"  {rname} = 0x{addr:016x}: ")
            data = b""
            for i in range(4):
                val = int(gdb.parse_and_eval(f"*(unsigned long*)0x{addr + i*8:x}")) & 0xFFFFFFFFFFFFFFFF
                data += val.to_bytes(8, "little")
            gdb.write(f"{data[:32].hex()}\n")
            # Try as string
            nul_pos = data.find(b'\x00')
            if nul_pos >= 0:
                s = data[:nul_pos].decode("ascii", errors="replace")
                gdb.write(f"         string: \"{s}\"\n")
            else:
                gdb.write(f"         NO NUL in first 32 bytes!\n")
        else:
            gdb.write(f"  {rname} = 0x{addr:016x}: <not a kernel address>\n")
    except Exception as e:
        gdb.write(f"  {rname}: <cannot read: {e}>\n")

# Dump klog
gdb.write("\n[klog] Dumping klog to /tmp/klog_strlen_debug.bin\n")
try:
    gdb.execute("dump binary memory /tmp/klog_strlen_debug.bin 0x810D0000 0x81100000")
    gdb.write("[klog] Dumped 192KB\n")
except gdb.error as err:
    gdb.write(f"[klog] dump error: {err}\n")

# Also save full output to file
gdb.write("\n[done] strlen debug session complete\n")
end

quit
