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

# --- Strategy: Read PAs via CPU ld (no MPRV needed) ---
# In debug mode, ld goes through D-cache → L2 → DDR
# This gives us the actual L2 cached data that SBA can't see

READER = 0x80038000
# ld a1, 0(a0); ebreak  (skip fence.i after first use)
instrs = [0x0000100f, 0x00053583, 0x00100073]  # fence.i, ld a1, 0(a0), ebreak
for i, insn in enumerate(instrs):
    gdb.execute(f"set *(unsigned int*)0x{READER + i*4:x} = 0x{insn:08x}")

# First call with fence.i
gdb.execute(f"set $a0 = 0x{READER:x}")
gdb.execute(f"set $pc = 0x{READER:x}")
gdb.execute(f"hbreak *0x{READER + 8:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.write("[init] Reader ready\n")

def read_pa_cpu(pa):
    """Read 8 bytes from PA via CPU ld (goes through D-cache/L2)"""
    gdb.execute(f"set $a0 = 0x{pa:x}")
    gdb.execute(f"set $pc = 0x{READER + 4:x}")  # skip fence.i
    gdb.execute(f"hbreak *0x{READER + 8:x}")
    gdb.execute("continue")
    val = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
    gdb.execute("delete breakpoints")
    return val

# --- KEY TEST: Compare SBA read vs CPU ld read for known data ---
gdb.write("\n=== SBA vs CPU ld comparison ===\n")

test_addrs = {
    "OpenSBI entry (0x80000000)": 0x80000000,
    "Image start (0x80200000)": 0x80200000,
    "DTB magic (0x84000000)": 0x84000000,
    "log_buf PA (0x80ebf368)": 0x80ebf368,
    "log_buf_len PA (0x80ebf360)": 0x80ebf360,
    "__log_buf PA (0x80ed0060)": 0x80ed0060,
}

for name, pa in test_addrs.items():
    # SBA read
    tmp = "/tmp/_sba_cmp.bin"
    gdb.execute(f"dump binary memory {tmp} 0x{pa:x} 0x{pa+8:x}", to_string=True)
    with open(tmp, "rb") as f:
        sba_val = struct.unpack("<Q", f.read(8))[0]
    
    # CPU ld read
    cpu_val = read_pa_cpu(pa)
    
    match = "MATCH" if sba_val == cpu_val else "DIFFER!"
    gdb.write(f"  {name:35s} SBA=0x{sba_val:016x} CPU=0x{cpu_val:016x} {match}\n")

# --- Read kernel data via CPU ld at CORRECT PAs ---
gdb.write("\n=== Kernel variables via CPU ld (PA) ===\n")

# PA = VA - 0xffffffff80000000 + 0x80200000 for kernel text/data
vars_pa = [
    ("log_buf",              0x80ebf368),
    ("log_buf_len",          0x80ebf360),
    ("__log_buf[0:8]",       0x80ed0060),
    ("__log_buf[8:16]",      0x80ed0068),
    ("saved_command_line",   0x80b18468),
    ("oops_count",           0x80ec0240),
]

# Get jiffies_64 and system_state actual PAs via nm
import subprocess
nm_proc = subprocess.run(["/opt/conda/envs/firemarshal/riscv-tools/bin/riscv64-unknown-linux-gnu-nm",
                          "/root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux"],
                         capture_output=True, text=True)
for line in nm_proc.stdout.split('\n'):
    parts = line.split()
    if len(parts) >= 3:
        va = int(parts[0], 16)
        sym = parts[2]
        pa = (va - 0xffffffff80000000 + 0x80200000) & 0xFFFFFFFFFFFFFFFF
        if sym == 'jiffies_64':
            vars_pa.append(("jiffies_64", pa))
        elif sym == 'system_state':
            vars_pa.append(("system_state", pa))
        elif sym == 'init_task':
            vars_pa.append(("init_task.state", pa))
            vars_pa.append(("init_task+0x358", pa + 0x358))  # .comm offset
        elif sym == 'nr_threads':
            vars_pa.append(("nr_threads", pa))

for name, pa in vars_pa:
    try:
        val = read_pa_cpu(pa)
        bval = val.to_bytes(8, "little")
        asc = "".join(chr(b) if 32 <= b < 127 else "." for b in bval)
        gdb.write(f"  {name:25s} PA=0x{pa:08x} = 0x{val:016x}  [{asc}]\n")
    except Exception as e:
        gdb.write(f"  {name:25s} ERROR: {e}\n")

# --- Read first 256 bytes of __log_buf via CPU ld ---
gdb.write("\n=== __log_buf (256 bytes via CPU ld) ===\n")
log_data = b""
for off in range(0, 256, 8):
    try:
        w = read_pa_cpu(0x80ed0060 + off)
        log_data += w.to_bytes(8, "little")
    except:
        break

for i in range(0, len(log_data), 16):
    chunk = log_data[i:i+16]
    hex_str = " ".join(f"{b:02x}" for b in chunk)
    asc_str = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
    gdb.write(f"  {i:04x}: {hex_str:48s} {asc_str}\n")

# --- If log_buf is non-zero, follow and read actual log ---
log_buf = None
try:
    log_buf = read_pa_cpu(0x80ebf368)
except:
    pass

if log_buf and log_buf > 0xffffffc000000000:
    # Convert log_buf VA to PA
    if log_buf >= 0xffffffd800000000 and log_buf < 0xffffffd900000000:
        buf_pa = log_buf - 0xffffffd800000000 + 0x80000000
    elif log_buf >= 0xffffffff80000000:
        buf_pa = (log_buf - 0xffffffff80000000 + 0x80200000) & 0xFFFFFFFFFFFFFFFF
    else:
        buf_pa = 0
    
    if buf_pa > 0x80000000 and buf_pa < 0x90000000:
        gdb.write(f"\n=== log_buf contents (VA=0x{log_buf:x} PA=0x{buf_pa:x}) ===\n")
        buf_data = b""
        for off in range(0, 512, 8):
            try:
                w = read_pa_cpu(buf_pa + off)
                buf_data += w.to_bytes(8, "little")
            except:
                break
        for i in range(0, len(buf_data), 16):
            chunk = buf_data[i:i+16]
            hex_str = " ".join(f"{b:02x}" for b in chunk)
            asc_str = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
            gdb.write(f"  {i:04x}: {hex_str:48s} {asc_str}\n")

gdb.write("\n[done]\n")
end

quit
