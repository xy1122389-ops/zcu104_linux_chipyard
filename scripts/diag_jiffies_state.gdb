set pagination off
set confirm off
set remotetimeout 60

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import gdb, os, re, struct, subprocess, time

host = os.environ.get("JLINK_HOST", "172.19.128.1")
port = int(os.environ.get("JLINK_PORT", "2331"))
VMLINUX = "/root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux"
NM = "/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-nm"

gdb.execute(f"target remote {host}:{port}")
gdb.execute("monitor halt")
time.sleep(1)

for name, num in [("satp", 0x180), ("scause", 0x142), ("sepc", 0x141),
                  ("mcause", 0x342), ("mepc", 0x341), ("dcsr", 0x7b0), ("dpc", 0x7b1)]:
    out = gdb.execute(f"monitor ReadCSR 0x{num:x}", to_string=True).strip()
    gdb.write(f"[csr] {name:8s} = {out}\n")

mstatus_out = gdb.execute("monitor ReadCSR 0x300", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', mstatus_out)
if not m:
    raise gdb.GdbError("Cannot parse mstatus")
mstatus = int(m.group(1), 16)
new_mstatus = mstatus | (1 << 17)
new_mstatus = (new_mstatus & ~(3 << 11)) | (1 << 11)

READER = 0x80038000
code = [
    0x0000100f,
    0x00053583,
    0x00100073,
]
for i, insn in enumerate(code):
    gdb.execute(f"set *(unsigned int*)0x{READER + i*4:x} = 0x{insn:08x}")

gdb.execute(f"monitor WriteCSR 0x300 0x{new_mstatus:x}")
gdb.execute(f"set $a0 = 0x{READER:x}")
gdb.execute(f"set $pc = 0x{READER:x}")
gdb.execute(f"hbreak *0x{READER + 8:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.execute(f"monitor WriteCSR 0x300 0x{new_mstatus:x}")

def read_va_u64(va):
    gdb.execute(f"set $a0 = 0x{va:x}")
    gdb.execute(f"set $pc = 0x{READER + 4:x}")
    gdb.execute(f"hbreak *0x{READER + 8:x}")
    gdb.execute("continue")
    val = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
    gdb.execute("delete breakpoints")
    gdb.execute(f"monitor WriteCSR 0x300 0x{new_mstatus:x}")
    return val

symbols = {}
for line in subprocess.check_output([NM, "-n", VMLINUX], text=True).splitlines():
    parts = line.split()
    if len(parts) == 3:
        try:
            symbols[parts[2]] = int(parts[0], 16)
        except ValueError:
            pass

want = ["jiffies_64", "system_state", "log_buf", "log_buf_len", "__log_buf"]
gdb.write("\n=== Runtime variables ===\n")
for sym in want:
    va = symbols.get(sym)
    if va is None:
        gdb.write(f"[sym] {sym:12s} = missing\n")
        continue
    val = read_va_u64(va)
    b = val.to_bytes(8, "little")
    asc = "".join(chr(x) if 32 <= x < 127 else "." for x in b)
    gdb.write(f"[sym] {sym:12s} VA=0x{va:016x} VAL=0x{val:016x} [{asc}]\n")

log_buf_va = symbols.get("__log_buf")
if log_buf_va is not None:
    gdb.write("\n=== __log_buf[0:64] ===\n")
    data = bytearray()
    for off in range(0, 64, 8):
        data.extend(read_va_u64(log_buf_va + off).to_bytes(8, "little"))
    for off in range(0, 64, 16):
        chunk = data[off:off+16]
        hexs = " ".join(f"{x:02x}" for x in chunk)
        asc = "".join(chr(x) if 32 <= x < 127 else "." for x in chunk)
        gdb.write(f"  {off:04x}: {hexs:47s} {asc}\n")

gdb.execute(f"monitor WriteCSR 0x300 0x{mstatus:x}")
gdb.write("\n[done]\n")
end

quit