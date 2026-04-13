# quick_klog_dump.gdb — Dump kernel log from already-booted kernel
# Reconnects to halted CPU, reads printk ring buffer, saves to file

set pagination off
set confirm off
set remotetimeout 30

python
import os, gdb, time, struct, subprocess

host = os.environ.get("JLINK_HOST", "172.19.128.1")
port = int(os.environ.get("JLINK_PORT", "2331"))
gdb.execute(f"target remote {host}:{port}")
gdb.execute("monitor halt")
time.sleep(0.5)

# Get current PC to confirm kernel state
gdb.execute("maintenance flush register-cache")
pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"[klog] PC = 0x{pc:016x}\n")

# Read key kernel variables via SBA at physical addresses
# We need vmlinux symbols. Try nm approach.
vmlinux = "/root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux"
try:
    nm_out = subprocess.check_output(
        ["/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-nm", "-n", vmlinux],
        text=True, timeout=10
    )
    syms = {}
    for line in nm_out.strip().split("\n"):
        parts = line.split()
        if len(parts) >= 3:
            syms[parts[2]] = int(parts[0], 16)
    
    # VA to PA: PA = VA - 0xffffffff80000000 + 0x80200000
    def va2pa(va):
        return (va - 0xffffffff80000000 + 0x80200000) & 0xFFFFFFFFFFFFFFFF
    
    # Key symbols
    for name in ["log_buf", "__log_buf", "log_buf_len_get", "system_state", "oops_count", "jiffies_64", "init_task"]:
        if name in syms:
            gdb.write(f"[sym] {name} = VA 0x{syms[name]:016x} PA 0x{va2pa(syms[name]):016x}\n")
    
    # Read system_state
    if "system_state" in syms:
        pa = va2pa(syms["system_state"])
        ss = int(gdb.parse_and_eval(f"*(unsigned int*)0x{pa:x}"))
        gdb.write(f"[klog] system_state = {ss}\n")
    
    # Read oops_count
    if "oops_count" in syms:
        pa = va2pa(syms["oops_count"])
        oc = int(gdb.parse_and_eval(f"*(unsigned int*)0x{pa:x}"))
        gdb.write(f"[klog] oops_count = {oc}\n")
    
    # Read log_buf pointer (may have been reallocated)
    if "log_buf" in syms:
        pa = va2pa(syms["log_buf"])
        log_buf_va = int(gdb.parse_and_eval(f"*(unsigned long long*)0x{pa:x}")) & 0xFFFFFFFFFFFFFFFF
        gdb.write(f"[klog] log_buf VA = 0x{log_buf_va:016x}\n")
        log_buf_pa = va2pa(log_buf_va)
        gdb.write(f"[klog] log_buf PA = 0x{log_buf_pa:016x}\n")
        
        # Dump 64KB from log_buf
        dump_size = 65536
        outfile = f"/tmp/klog_quick_{int(time.time())}.bin"
        gdb.execute(f"dump binary memory {outfile} 0x{log_buf_pa:x} 0x{log_buf_pa + dump_size:x}")
        gdb.write(f"[klog] Dumped {dump_size} bytes to {outfile}\n")
        gdb.write(f"[klog] Run: strings {outfile} | head -100\n")
    
except Exception as e:
    gdb.write(f"[klog] Error: {e}\n")
    # Fallback: dump from __log_buf at known offset
    gdb.write("[klog] Trying fallback __log_buf dump...\n")

end

disconnect
quit
