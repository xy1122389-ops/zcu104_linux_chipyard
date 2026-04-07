# linux_boot_continue.gdb — Continue Boot 24 from Linux _start
# CPU already at 0x80200000, firmware/DTB loaded, DDR zeroed
# This script applies patches, clears dcsr, and launches kernel.

set pagination off
set confirm off
set remotetimeout 600

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import gdb
_host = "172.19.128.1"
_port = 12331
gdb.write(f"[info] Connecting to J-Link at {_host}:{_port}\n")
gdb.execute(f"target remote {_host}:{_port}")
end

echo --- Boot 24 continue ---\n
info reg pc

python
import gdb, re, time

_host = "172.19.128.1"
_port = 12331

pc = int(gdb.parse_and_eval("$pc"))
gdb.write(f"[check] PC = 0x{pc:x}\n")
if pc != 0x80200000:
    gdb.write("[WARN] PC is not 0x80200000! Proceeding anyway.\n")

# ==========================================================
# Phase 5.5: Apply GDB patches for known crash workarounds
# ==========================================================
gdb.write("\n=== Phase 5.5: Apply GDB patches ===\n")

RET0 = 0x80824501
patches = [
    (0x80601168, 0x00000013, "NOP parse_args call in initcall loop"),
    (0x806162d0, RET0, "legacy_pty_init -> return 0"),
    (0x80616440, RET0, "unix98_pty_init -> return 0"),
    (0x805b891e, RET0, "__warn -> return immediately"),
]

for pa, val, desc in patches:
    try:
        old = int(gdb.parse_and_eval(f"*(unsigned int*){pa}"))
        gdb.execute(f"set *(unsigned int*){pa} = {val}")
        new = int(gdb.parse_and_eval(f"*(unsigned int*){pa}"))
        gdb.write(f"[patch] {desc}: PA 0x{pa:x} old=0x{old:08x} new=0x{new:08x}\n")
    except Exception as e:
        gdb.write(f"[patch] FAILED {desc}: {e}\n")

# Replace strlen with safe version
strlen_pa = 0x805b7ea0
strlen_words = [0x43e55593, 0xc1990585, 0x80824501, 0x460385aa,
                0xc2190005, 0xbfe50505, 0x80828d0d]
gdb.write(f"[patch] Replacing strlen with safe version (28 bytes at PA 0x{strlen_pa:x})...\n")
try:
    for i, w in enumerate(strlen_words):
        gdb.execute(f"set *(unsigned int*)({strlen_pa + i*4}) = {w}")
    v0 = int(gdb.parse_and_eval(f"*(unsigned int*){strlen_pa}"))
    v6 = int(gdb.parse_and_eval(f"*(unsigned int*)({strlen_pa + 24})"))
    gdb.write(f"[patch] strlen: first=0x{v0:08x} (exp 0x43e55593), last=0x{v6:08x} (exp 0x80828d0d)\n")
    if v0 == 0x43e55593 and v6 == 0x80828d0d:
        gdb.write("[patch] strlen replacement OK\n")
    else:
        gdb.write("[patch] strlen replacement MISMATCH!\n")
except Exception as e:
    gdb.write(f"[patch] strlen replacement FAILED: {e}\n")

# ==========================================================
# Phase 6: Clear dcsr ebreak bits
# ==========================================================
gdb.write("\n=== Phase 6: Clear dcsr ebreak bits ===\n")

read_out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
gdb.write(f"[dcsr] Before: {read_out.strip()}\n")

m = re.search(r'(?:0x)?([0-9A-Fa-f]{8})', read_out)
if not m:
    raise gdb.GdbError(f"Cannot parse dcsr from: {read_out.strip()}")
old_dcsr = int(m.group(1), 16)

EBREAK_MASK = (1 << 15) | (1 << 13) | (1 << 12)
new_dcsr = old_dcsr & ~EBREAK_MASK
gdb.write(f"[dcsr] old=0x{old_dcsr:08X} -> new=0x{new_dcsr:08X} (cleared bits 15,13,12)\n")

gdb.execute(f"monitor WriteCSR 0x7b0 0x{new_dcsr:08X}")
verify_out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
gdb.write(f"[dcsr] After:  {verify_out.strip()}\n")
gdb.write("[OK] dcsr ebreak bits cleared\n")

# ==========================================================
# Phase 7: Launch kernel, poll klog progress every 120s
# ==========================================================
gdb.write("\n=== Phase 7: Launch kernel + polling dmesg dump ===\n")
gdb.write("Kernel will run freely. Poll every 120s, max 3600s total.\n")

POLL_INTERVAL = 120
MAX_TOTAL     = 3600
STALL_LIMIT   = 8
LOG_PA        = 0x80ed4060
LOG_LEN       = 0x20000
LOG_BUF_PTR   = 0x80ec25e8
LOG_BUF_LEN   = 0x80ec25e0

gdb.execute("delete breakpoints")

# Use interrupt-based polling: keep GDB connected, use continue/interrupt cycle
gdb.write("[boot] Starting kernel with interrupt-based polling...\n")

elapsed = 0
stall_count = 0
prev_used = 0
poll_num = 0

# Initial resume
gdb.execute("continue &")

while elapsed < MAX_TOTAL:
    wait = min(POLL_INTERVAL, MAX_TOTAL - elapsed)
    gdb.write(f"[poll] Waiting {wait}s (elapsed {elapsed}/{MAX_TOTAL}s)...\n")
    time.sleep(wait)
    elapsed += wait

    poll_num += 1
    gdb.write(f"\n[poll {poll_num}] Interrupting at t={elapsed}s...\n")

    # Interrupt the running target
    try:
        gdb.execute("interrupt")
        time.sleep(2)  # Give time for halt
    except Exception as e:
        gdb.write(f"[poll {poll_num}] Interrupt failed: {e}\n")
        stall_count += 1
        if stall_count >= STALL_LIMIT:
            gdb.write("[poll] Too many failures, aborting.\n")
            break
        continue

    try:
        pc_val = int(gdb.parse_and_eval("$pc"))
        gdb.write(f"[poll {poll_num}] PC = 0x{pc_val & 0xFFFFFFFFFFFFFFFF:016x}\n")
    except:
        gdb.write(f"[poll {poll_num}] PC read failed\n")
        pc_val = 0

    try:
        gdb.execute("set $satp = 0")
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
        gdb.write(f"[poll {poll_num}] klog used: ~{used_bytes} bytes (prev: {prev_used})\n")
    except Exception as e:
        gdb.write(f"[poll {poll_num}] klog scan error: {e}\n")
        used_bytes = -1

    if used_bytes > prev_used:
        stall_count = 0
        gdb.write(f"[poll {poll_num}] Kernel progressing (+{used_bytes - prev_used} bytes). Resuming.\n")
        prev_used = used_bytes
    elif used_bytes == prev_used and used_bytes >= 0:
        stall_count += 1
        gdb.write(f"[poll {poll_num}] Klog stalled ({stall_count}/{STALL_LIMIT}). ")
        if stall_count >= STALL_LIMIT:
            gdb.write("Giving up.\n")
            break
        else:
            gdb.write("Resuming.\n")
    else:
        stall_count += 1

    try:
        scause = int(gdb.parse_and_eval("$scause")) & 0xFFFFFFFFFFFFFFFF
        if scause != 0:
            gdb.write(f"[poll {poll_num}] scause = 0x{scause:x} — possible exception!\n")
    except:
        pass

    # Resume kernel
    try:
        gdb.execute("continue &")
    except Exception as e:
        gdb.write(f"[poll {poll_num}] Resume error: {e}\n")
        break

# ---- Final dump ----
gdb.write(f"\n=== Final dump at t={elapsed}s ===\n")

try:
    pc_val = int(gdb.parse_and_eval("$pc"))
    gdb.write(f"[final] PC = 0x{pc_val & 0xFFFFFFFFFFFFFFFF:016x}\n")
except:
    gdb.write("[final] Cannot read PC\n")

try:
    gdb.execute("set $satp = 0")
except:
    pass

# Dump klog
gdb.write("[final] Dumping klog...\n")
try:
    gdb.execute(f"dump binary memory /tmp/klog_latest.bin {LOG_PA} {LOG_PA + LOG_LEN}")
    gdb.write(f"[final] klog dumped to /tmp/klog_latest.bin ({LOG_LEN} bytes)\n")
except Exception as e:
    gdb.write(f"[final] klog dump error: {e}\n")

gdb.write("\n=== Boot 24 complete ===\n")
end
