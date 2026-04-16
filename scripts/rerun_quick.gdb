# rerun_quick.gdb — Boot from preloaded DDR and grab a quick kernel log snapshot
# Assumes fw_payload.bin + DTB are already present in DDR.
set pagination off
set confirm off
set breakpoint auto-hw off
set remotetimeout 600

file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

python
import os, subprocess, gdb
host = os.environ.get("JLINK_HOST")
if not host:
	host = subprocess.check_output(
		["bash", "-lc", "ip route | awk '/default/ {print $3; exit}'"], text=True
	).strip() or "172.19.128.1"
port = os.environ.get("JLINK_PORT", "2331")
gdb.write(f"[info] Connecting to J-Link at {host}:{port}\n")
gdb.execute(f"target extended-remote {host}:{port}")
end

monitor halt
echo \n=== Quick Re-run: Restart from preloaded DDR ===\n
monitor WriteCSR 0x180 0

python
import gdb, os, re
dtb_addr = int(os.environ.get("DTB_ADDR", "0x84000000"), 0)
dtb_path = os.environ.get("DTB_PATH", "")
osbi_w0 = int(gdb.parse_and_eval("*(unsigned int*)0x80000000"))
linux_w0 = int(gdb.parse_and_eval("*(unsigned int*)0x80200000"))
gdb.write(f"[verify] OpenSBI @0x80000000 = 0x{osbi_w0:08X}\n")
gdb.write(f"[verify] Linux   @0x80200000 = 0x{linux_w0:08X}\n")
if dtb_path:
	gdb.write(f"[dtb] Restoring {dtb_path} -> 0x{dtb_addr:x}\n")
	gdb.execute(f"restore {dtb_path} binary 0x{dtb_addr:x}")
out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8})', out)
old_dcsr = int(m.group(1), 16) if m else 0x4000F081
new_dcsr = old_dcsr & ~((1 << 15) | (1 << 13) | (1 << 12))
gdb.write(f"[dcsr] 0x{old_dcsr:08X} -> 0x{new_dcsr:08X}\n")
gdb.execute(f"monitor WriteCSR 0x7b0 0x{new_dcsr:08X}")
dtb_magic = int(gdb.parse_and_eval(f"*(unsigned int*)0x{dtb_addr:x}"))
gdb.write(f"[verify] DTB     @0x{dtb_addr:x} = 0x{dtb_magic:08X}\n")
gdb.execute("delete breakpoints")
gdb.execute("hbreak *0x8000b2b2")
gdb.execute("hbreak *0x8000ad3c")
gdb.execute("set $pc = 0x80000000")
gdb.execute("set $a0 = 0")
gdb.execute(f"set $a1 = 0x{dtb_addr:x}")
gdb.execute("set $a2 = 0")
end

continue

echo \n=== OpenSBI handoff reached ===\n
printf "pc = 0x%lx\n", $pc
printf "a0(hartid) = %lx\n", $a0
printf "a1(dtb)    = 0x%lx\n", $a1

delete breakpoints

python
import os, time, gdb
run_secs = int(os.environ.get("KERNEL_RUN_SECS", "90"))
gdb.write(f"[run] Continuing kernel for {run_secs}s\n")
gdb.execute("continue &")
time.sleep(run_secs)
gdb.execute("interrupt")
end

echo \n=== Halted after timed run ===\n
printf "pc = 0x%lx\n", $pc
printf "scause = 0x%lx\n", $scause
printf "sepc   = 0x%lx\n", $sepc
printf "stval  = 0x%lx\n", $stval

python
import os, gdb
out_path = os.environ.get("KLOG_OUT", "/tmp/klog_rerun.bin")
start = int(os.environ.get("KLOG_START", "0x810D0000"), 0)
end = int(os.environ.get("KLOG_END", "0x81100000"), 0)
gdb.write(f"[dump] {out_path} <= 0x{start:x}-0x{end:x}\n")
gdb.execute(f"dump binary memory {out_path} 0x{start:x} 0x{end:x}")
end

echo [ok] timed klog snapshot dumped\n

quit
