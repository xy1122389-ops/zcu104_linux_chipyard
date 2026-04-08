# rerun_quick.gdb — Quick re-run from OpenSBI to check crash determinism
# Memory is still intact from previous SBA load, no need to reload
set pagination off
set confirm off

target extended-remote 172.19.128.1:2331
file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

echo \n=== Quick Re-run: Restart from OpenSBI ===\n

# Reset CPU to OpenSBI entry
set $pc = 0x80000000
set $a0 = 0

# Break at mret to verify OpenSBI works
hbreak *0x8000b2b2
continue

echo \n=== OpenSBI mret reached ===\n
printf "a0(hartid)=%lx  a1(dtb)=0x%lx\n", $a0, $a1

# Delete mret bp, let kernel run for 15 seconds
delete 1

python
import time
gdb.execute("continue &")
time.sleep(15)
gdb.execute("interrupt")
end

echo \n=== Halted after 15s ===\n
printf "pc = 0x%lx\n", $pc

# Check scause for trap info
printf "scause = 0x%lx\n", $scause
printf "sepc   = 0x%lx\n", $sepc
printf "stval  = 0x%lx\n", $stval

# Dump klog from __log_buf PA
# For no-RVC kernel: __log_buf PA = 0x810D0060
echo \n=== Dumping klog ===\n
dump binary memory /tmp/klog_rerun.bin 0x810D0000 0x81100000
echo [ok] klog dumped to /tmp/klog_rerun.bin\n

quit
