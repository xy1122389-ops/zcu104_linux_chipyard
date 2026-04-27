# manual_load_and_boot.gdb
# Purpose: Bypass failed sd_loader, load fw_payload+DTB via SBA, boot OpenSBI
# Usage: riscv64-unknown-elf-gdb -q -batch -x scripts/manual_load_and_boot.gdb
#
# Prereqs:
#   - J-Link GDB Server running on port 3333 (scripts/start_jlink_server.sh)
#   - PS DDR initialized (run_ps_ddr_init.sh or phase1_verify_ps_chain.sh)
#   - Rocket in trap loop (PC=0) — normal after sd_loader fails

set pagination off
set confirm off
set breakpoint auto-hw off
set remotetimeout 1200

echo === Connecting to J-Link GDB Server at 127.0.0.1:3333 ===\n
target remote 127.0.0.1:3333

echo === Halting CPU ===\n
monitor halt
echo --- CPU state before load ---\n
info reg pc ra sp a0 a1

# ============================================================
# Phase 1: Load fw_payload.bin → 0x80000000
# ============================================================
echo \n=== Phase 1: Loading fw_payload.bin → 0x80000000 (may take 15+ min) ===\n
restore /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin binary 0x80000000
echo [OK] fw_payload.bin loaded\n

# ============================================================
# Phase 2: Load DTB → 0x84000000
# ============================================================
echo \n=== Phase 2: Loading DTB → 0x84000000 ===\n
restore /root/chipyard/fpga/linux-bringup/dtb/chipyard-zcu104-linux-slip.dtb binary 0x84000000
echo [OK] DTB loaded\n

# Verify key addresses
echo === Verifying DDR content ===\n
x/4wx 0x80000000
x/4wx 0x84000000

# ============================================================
# Phase 3: fence.i via safe address
# ============================================================
echo \n=== Phase 3: fence.i (flush I-cache) ===\n
set *(unsigned int*)0x80100000 = 0x0000100f
set *(unsigned short*)0x80100004 = 0x9002
set $pc = 0x80100000
stepi
echo [OK] fence.i executed, pc now:
info reg pc

# ============================================================
# Phase 4: Set up registers and jump to OpenSBI
# ============================================================
echo \n=== Phase 4: Set registers → boot from 0x80000000 ===\n
set $a0 = 0
set $a1 = 0x84000000
set $a2 = 0
set $pc = 0x80000000

echo [boot] a0=0 (hartid), a1=0x84000000 (DTB), pc=0x80000000 (OpenSBI)\n
info reg pc a0 a1

# ============================================================
# Phase 5: Clear dcsr ebreak bits, preserve M-mode (prv=3)
# ============================================================
echo \n=== Phase 5: Fix dcsr (clear ebreak bits, prv=M) ===\n
python
import gdb
out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
gdb.write(f"[dcsr] read: {out.strip()}\n")
# Parse current value
val = 0
for tok in out.split():
    try:
        val = int(tok, 16)
        break
    except ValueError:
        pass
# Clear bits 15(ebreakm), 13(ebreaks), 12(ebreaku), but set prv=3(M-mode)
new_val = (val & ~((1<<15)|(1<<13)|(1<<12))) | 0x3
gdb.write(f"[dcsr] old=0x{val:08X} new=0x{new_val:08X}\n")
gdb.execute(f"monitor WriteCSR 0x7b0 0x{new_val:X}")
end

echo \n=== Phase 6: Launch with continue & (background, non-blocking) ===\n
echo [boot] Starting OpenSBI at 0x80000000 in background...\n

python
import time, gdb
gdb.execute("continue &")
gdb.write("[OK] CPU running (background continue)\n")
for i in range(30):
    time.sleep(10)
    gdb.write(f"[wait] {(i+1)*10}s elapsed\n")
end

echo \n=== Phase 7: Halt and check PC ===\n
monitor halt
info reg pc ra a0 a1
x/4wx 0x80000000
x/4wx 0x84000000

echo \n=== Done. Check PC — expect 0x8xxxxxxx (Linux running) ===\n
disconnect
quit
