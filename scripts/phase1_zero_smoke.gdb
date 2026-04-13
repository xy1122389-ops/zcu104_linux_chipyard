set pagination off
set confirm off
set breakpoint auto-hw off
set remotetimeout 120

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
        gdb.write(f"[warn] Connect attempt {attempt} failed: {err}\n")
        if attempt < 3:
            time.sleep(2)
if last_error is not None:
    raise last_error
end

monitor halt
echo --- Initial state ---\n
info reg pc

echo \n=== Phase 1 Zero Smoke ===\n
monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

set *(unsigned int*)0x80038000 = 0x00053023
set *(unsigned short*)0x80038004 = 0x0521
set *(unsigned int*)0x80038006 = 0xFEB54DE3
set *(unsigned short*)0x8003800A = 0x9002

set *(unsigned int*)0x80038100 = 0x0000100f
set *(unsigned short*)0x80038104 = 0x9002
set *(unsigned long long*)0x2010200 = 0x80038000
set *(unsigned long long*)0x2010200 = 0x80038040
set *(unsigned long long*)0x2010200 = 0x80038100

set $pc = 0x80038100
stepi
echo [ok] fence.i\n

delete breakpoints
hbreak *0x8003800a

echo [test0] small range 0x80040000-0x80042000...\n
set $a0 = 0x80040000
set $a1 = 0x80042000
set $pc = 0x80038000
continue
echo [test0] done\n
info reg pc a0 a1

echo [test1] zero0 full range 0x80040000-0x80200000...\n
set $a0 = 0x80040000
set $a1 = 0x80200000
set $pc = 0x80038000
continue
echo [test1] done\n
info reg pc a0 a1

echo [done]\n
detach
quit