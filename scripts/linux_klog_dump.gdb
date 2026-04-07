# linux_klog_dump.gdb — Dump kernel log from halted Rocket core
# Run after linux_boot.gdb has launched the kernel and been killed/timed out.
# This script connects, halts the core, reads PC/CSRs, and dumps klog.
#
# Usage: riscv64-unknown-elf-gdb -batch -x scripts/linux_klog_dump.gdb

set pagination off
set confirm off
set remotetimeout 30

python
import gdb, re

_host = "172.19.128.1"
_port = 12331

LOG_PA      = 0x80ed4060
LOG_LEN     = 0x20000
LOG_BUF_PTR = 0x80ec25e8
LOG_BUF_LEN = 0x80ec25e0

gdb.write(f"[info] Connecting to {_host}:{_port}...\n")
gdb.execute(f"target remote {_host}:{_port}")

# Target is now halted (J-Link halts on connect)
gdb.write("[info] Target halted.\n")

# Clear satp for PA access
try:
    gdb.execute("set $satp = 0")
except:
    pass

# Read PC
try:
    pc = int(gdb.parse_and_eval("$pc"))
    gdb.write(f"[state] PC = 0x{pc & 0xFFFFFFFFFFFFFFFF:016x}\n")
except:
    gdb.write("[state] PC read failed\n")

# Read CSRs
for name, reg in [("satp", "$satp"), ("scause", "$scause"), ("sepc", "$sepc"),
                   ("stval", "$stval"), ("sstatus", "$sstatus")]:
    try:
        val = int(gdb.parse_and_eval(reg))
        gdb.write(f"[state] {name} = 0x{val & 0xFFFFFFFFFFFFFFFF:016x}\n")
    except:
        pass

# Quick klog size estimate
try:
    checkpoints = [1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072]
    used_bytes = 0
    for cp in checkpoints:
        if cp > LOG_LEN:
            break
        addr = LOG_PA + cp - 1
        val = int(gdb.parse_and_eval(f"*(unsigned char*)({addr})"))
        if val != 0:
            used_bytes = cp
        else:
            break
    gdb.write(f"[klog] Estimated used: ~{used_bytes} bytes\n")
except Exception as e:
    gdb.write(f"[klog] Size estimate failed: {e}\n")
    used_bytes = 0

# Read log_buf pointer
try:
    log_buf_val = int(gdb.parse_and_eval(f"*(unsigned long long*){LOG_BUF_PTR}"))
    log_buf_len = int(gdb.parse_and_eval(f"*(unsigned int*){LOG_BUF_LEN}"))
    gdb.write(f"[log] log_buf = 0x{log_buf_val:016x}\n")
    gdb.write(f"[log] log_buf_len = 0x{log_buf_len:x}\n")
except:
    log_buf_val = 0
    log_buf_len = 0

# Determine PA
log_pa = LOG_PA
if log_buf_val != 0 and log_buf_val != 0xffffffff80cd4060:
    computed = (log_buf_val - 0xffffffff80000000 + 0x80200000) & 0xFFFFFFFFFFFFFFFF
    if 0x80000000 <= computed <= 0xFFFFFFFF:
        log_pa = computed
        gdb.write(f"[log] Relocated log_buf PA = 0x{log_pa:x}\n")

dump_sz = LOG_LEN
if 0 < log_buf_len <= 0x200000:
    dump_sz = log_buf_len

# Dump klog
gdb.write(f"[dump] Dumping {dump_sz} bytes from PA 0x{log_pa:x}...\n")
gdb.execute(f"dump binary memory /tmp/klog_latest.bin {log_pa} {log_pa + dump_sz}")
gdb.write("[dump] Saved to /tmp/klog_latest.bin\n")

if log_pa != LOG_PA:
    gdb.execute(f"dump binary memory /tmp/klog_static.bin {LOG_PA} {LOG_PA + LOG_LEN}")

# Extract readable strings
gdb.write("\n[strings] Extracting readable strings from klog...\n")
end

shell python3 -c "import re; data=open('/tmp/klog_latest.bin','rb').read(); strings=[s.decode() for s in re.findall(rb'[\x20-\x7e]{8,}', data[:131072])]; print(f'Found {len(strings)} strings in klog'); [print(f'  {i:3d}: {s[:120]}') for i,s in enumerate(strings[-40:])]"

echo \n=== klog dump complete ===\n
echo Check /tmp/klog_latest.bin for full binary dump.\n
echo Use: python3 -c "import re; data=open('/tmp/klog_latest.bin','rb').read(); [print(s.decode()) for s in re.findall(rb'[\\x20-\\x7e]{8,}', data)]"\n
