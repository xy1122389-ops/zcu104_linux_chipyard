# linux_boot.gdb — ZCU104 Rocket Minimal Linux Boot (Phase 1: no binary patches)
#
# Prerequisites:
#   1. run_ps_ddr_init.sh — PS DDR init + bitstream download
#   2. J-Link GDB Server / relay running
#
# What this script does:
#   Phase 1: Zero uninitialized DDR regions via Rocket core
#   Phase 2: Restore fw_payload.bin (15MB) + DTB via SBA
#   Phase 3: L2 cache invalidation for restored regions
#   Phase 4: fence.i
#   Phase 5: Boot OpenSBI -> mret -> Linux
#   Phase 6: Clear dcsr ebreak bits
#   Phase 7: Run kernel for a timed interval
#   Phase 8: Dump printk ring buffer in the same session

set pagination off
set confirm off
set breakpoint auto-hw off
set remotetimeout 600

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import os, gdb, time

host = os.environ.get("JLINK_HOST", "127.0.0.1")
relay_port = int(os.environ.get("JLINK_PORT", "3333"))
cfg_name = os.environ.get("CHIPYARD_ZCU104_CFG", "")
skip_l2_env = os.environ.get("SKIP_L2")
VMLINUX = "/root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux"
if skip_l2_env is None:
    skip_l2 = 1 if "NoL2" in cfg_name else 0
else:
    skip_l2 = int(skip_l2_env)

if not os.path.exists(VMLINUX):
    raise gdb.GdbError(
        f"[preflight] Missing linux-clean vmlinux: {VMLINUX}. Rebuild it before running linux_boot.gdb."
    )

gdb.execute(f"set $skip_l2 = {skip_l2}")
gdb.write(f"[info] Connecting to J-Link at {host}:{relay_port}\n")
last_error = None
for attempt in range(1, 4):
    try:
        gdb.execute(f"target remote {host}:{relay_port}")
        gdb.write(f"[info] J-Link connected on attempt {attempt}\n")
        last_error = None
        break
    except gdb.error as err:
        last_error = err
        gdb.write(f"[warn] Connect attempt {attempt} failed: {err}\n")
        if attempt < 3:
            time.sleep(2)
if last_error is not None:
    raise last_error
if cfg_name:
    gdb.write(f"[cfg] CHIPYARD_ZCU104_CFG={cfg_name}\n")
gdb.write(f"[cfg] skip_l2={skip_l2}\n")
end

monitor halt
echo --- Initial state ---\n
info reg pc

# ============================================================
# Hart 1 SMP bootstrap setup (sdboot-based mechanism)
# ============================================================
# The TLROM contains sdboot (baremetal.c), not testchipip BootROM.
# Both harts run sdboot head.S -> main(). Hart 1 polls 0x80001000 for payload.
# We will write DDR_TEST_PATTERN (0x11223344) to 0x80001000 BEFORE loading chunks
# (in Phase 2) so Hart 1 stays in the polling loop.
# After Hart 0 reaches OpenSBI mret (Phase 5.5), we restore the real sentinel value
# so Hart 1 jumps to 0x80000000, entering OpenSBI warmboot WFI.
# This ensures Hart 0 is the coldboot hart and Hart 1 enters warmboot properly.

# ============================================================
# Phase 1: Zero DDR via Rocket core
# ============================================================
echo \n=== Phase 1: Zero DDR via Rocket core ===\n

monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

# Safe scratch region above OpenSBI _fw_end (0x80037000)
# zero_loop: sd zero,0(a0); c.addi a0,8; blt a0,a1,loop; c.ebreak
set *(unsigned int*)0x80038000 = 0x00053023
set *(unsigned short*)0x80038004 = 0x0521
set *(unsigned int*)0x80038006 = 0xFEB54DE3
set *(unsigned short*)0x8003800A = 0x9002

# fence.i trampoline
set *(unsigned int*)0x80038100 = 0x0000100f
set *(unsigned short*)0x80038104 = 0x9002

if $skip_l2 == 0
set *(unsigned long long*)0x2010200 = 0x80038000
set *(unsigned long long*)0x2010200 = 0x80038040
set *(unsigned long long*)0x2010200 = 0x80038100
else
echo [L2flush] Skipped Phase 1 trampoline flush for no-L2 config\n
end

set $pc = 0x80038100
stepi
echo [ok] fence.i\n

delete breakpoints
hbreak *0x8003800A

echo [zero0] 0x80040000-0x80200000...\n
set $a0 = 0x80040000
set $a1 = 0x80200000
set $pc = 0x80038000
continue
echo [zero0] done\n

echo [zero1] 0x80EC4000-0x84000000...\n
set $a0 = 0x80EC4000
set $a1 = 0x84000000
set $pc = 0x80038000
continue
echo [zero1] done\n

echo [zero1b] 0x84001070-0x84100000...\n
set $a0 = 0x84001070
set $a1 = 0x84100000
set $pc = 0x80038000
continue
echo [zero1b] done\n

echo [zero2] 0x84100000-0xA0000000...\n
set $a0 = 0x84100000
set $a1 = 0xA0000000
set $pc = 0x80038000
continue
echo [zero2] done\n

echo [zero3] 0xA0000000-0xC0000000...\n
set $a0 = 0xA0000000
set $a1 = 0xC0000000
set $pc = 0x80038000
continue
echo [zero3] done\n

echo [zero4] 0xC0000000-0x100000000...\n
set $a0 = 0xC0000000
set $a1 = 0x100000000
set $pc = 0x80038000
continue
echo [zero4] done\n
echo [ALL DDR ZEROED]\n

# ============================================================
# Phase 2: Restore fw_payload.bin + DTB via SBA
# ============================================================
echo \n=== Phase 2: Restore fw_payload.bin (15MB via SBA) ===\n

monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

set *(unsigned int*)0x80038100 = 0x0000100f
set *(unsigned short*)0x80038104 = 0x9002
if $skip_l2 == 0
set *(unsigned long long*)0x2010200 = 0x80038100
else
echo [L2flush] Skipped Phase 2 trampoline flush for no-L2 config\n
end
set $pc = 0x80038100
stepi
echo [ok] fence.i\n

python
import os, gdb, time

chunk_dir = "/tmp/fw_chunks_v4"
base_addr = 0x80000000
chunk_size = 4194304
reconnect_every = 99
_host = os.environ.get("JLINK_HOST", "127.0.0.1")
_port = int(os.environ.get("JLINK_PORT", "3333"))

chunks = sorted([f for f in os.listdir(chunk_dir) if f.startswith("chunk_") and f.endswith(".bin")])
total = len(chunks)
gdb.write(f"[restore] Loading fw_payload.bin in {total} chunks (4MB each)...\n")

SENTINEL_ADDR   = 0x80001000
SENTINEL_HOLD   = 0x11223344   # DDR_TEST_PATTERN — keeps Hart 1 in BootROM polling loop
SENTINEL_REAL   = 0x6318972a   # Original fw_payload value at offset 0x1000 (OpenSBI code)
SENTINEL_OFFSET = SENTINEL_ADDR - base_addr  # = 0x1000 (byte offset in chunk_00)

for i, fname in enumerate(chunks):
    if i > 0 and i % reconnect_every == 0:
        gdb.write(f"[reconnect] Cycling J-Link connection after {i} chunks...\n")
        gdb.execute("disconnect")
        time.sleep(3)
        gdb.execute(f"target remote {_host}:{_port}")
        gdb.execute("monitor halt")
        gdb.write("[reconnect] OK\n")

    addr = base_addr + i * chunk_size
    fpath = os.path.join(chunk_dir, fname)
    fsize = os.path.getsize(fpath)
    gdb.write(f"[restore {i+1}/{total}] {fname} -> 0x{addr:08x} ({fsize} bytes)...\n")

    if i == 0:
        # chunk_00 contains the sentinel at offset 0x1000 (DDR 0x80001000 = OpenSBI code).
        # Strategy (fix9): patch the sentinel bytes in-memory before restoring,
        # so DDR[0x80001000] = DDR_TEST_PATTERN (0x11223344) throughout Phase 2 & 3.
        # This keeps Hart 1 in BootROM polling loop until Phase 2.75 restores the real value.
        import struct, tempfile
        chunk00_data = open(fpath, "rb").read()
        real_bytes = chunk00_data[SENTINEL_OFFSET:SENTINEL_OFFSET+4]
        real_val   = struct.unpack("<I", real_bytes)[0]
        gdb.write(f"[sentinel] chunk_00 offset 0x{SENTINEL_OFFSET:x}: real value = 0x{real_val:08x}\n")
        patched_data = chunk00_data[:SENTINEL_OFFSET] + struct.pack("<I", SENTINEL_HOLD) + chunk00_data[SENTINEL_OFFSET+4:]
        tmpfile = tempfile.mktemp(suffix="_chunk00_patched.bin")
        with open(tmpfile, "wb") as tf:
            tf.write(patched_data)
        gdb.write(f"[hart1-sentinel] Loading patched chunk_00 (0x80001000=0x{SENTINEL_HOLD:08x}, holds Hart 1 in polling)\n")
        gdb.execute(f"restore {tmpfile} binary 0x{addr:x}")
        os.unlink(tmpfile)
    else:
        gdb.execute(f"restore {fpath} binary 0x{addr:x}")

    gdb.write(f"[restore {i+1}/{total}] done\n")

gdb.write("[ok] fw_payload.bin restored (15MB in chunks)\n")
end

restore /root/chipyard/fpga/chipyard-zcu104-dualcore-smp.dtb binary 0x84000000
echo [ok] DTB restored at 0x84000000 (dual-core, maxcpus=1 for SMP bypass)\n

# External DTB at 0x84000000 carries bootargs overrides.
# Using maxcpus=1 DTB to bypass SMP bringup hang (SMP wait_for_completion_timeout
# appears to never expire — suspected NO_HZ_IDLE tickless issue with dual-core config).
# Hart 1 is still present in DTB (cpu@0 + cpu@1) but kernel won't try to online it.
# SMP will be re-enabled after root cause is found.
echo [dtb] External DTB provides chosen bootargs; will redirect a1 at mret\n

# NOTE: Phase 2.5 sentinel LOCK removed (fix8).
# 0x80001000 contains OpenSBI CODE (0x6318972a). Writing 0x11223344 there
# corrupts OpenSBI, causing it to hang and never reach mret.
# Hart 1 (BootROM) detecting 0x6318972a early is acceptable: it jumps to
# 0x80000000 (OpenSBI), loses the coldboot race to Hart 0, and enters warmboot WFI.

# ============================================================
# Phase 3: L2 cache invalidation after SBA restore
# ============================================================
echo \n=== Phase 3: Invalidate L2 cache for firmware region ===\n

if $skip_l2 == 0
set *(unsigned int*)0x80038000 = 0x00A63023
set *(unsigned int*)0x80038004 = 0x04050513
set *(unsigned int*)0x80038008 = 0xFEB54CE3
set *(unsigned short*)0x8003800C = 0x9002

set *(unsigned int*)0x80038100 = 0x0000100f
set *(unsigned short*)0x80038104 = 0x9002
set *(unsigned long long*)0x2010200 = 0x80038000
set *(unsigned long long*)0x2010200 = 0x80038040
set *(unsigned long long*)0x2010200 = 0x80038100
set $pc = 0x80038100
stepi
echo [ok] fence.i for L2 invalidation\n

delete breakpoints
hbreak *0x8003800C
set $a0 = 0x80000000
set $a1 = 0x80EC4000
set $a2 = 0x2010200
set $pc = 0x80038000
echo [L2inv] Invalidating L2 for firmware region (17MB)...\n
continue
echo [L2inv] Firmware region done\n

delete breakpoints
hbreak *0x8003800C
set $a0 = 0x84000000
set $a1 = 0x84002000
set $a2 = 0x2010200
set $pc = 0x80038000
echo [L2inv] Invalidating L2 for DTB region...\n
continue
echo [L2inv] DTB region done\n
else
echo [L2inv] Skipped for no-L2 config\n
end

# === Phase 2.75: Restore correct sentinel AFTER Phase 3 L2 flush ===
# CRITICAL: Must use CPU write (not SBA/monitor WriteU32) here.
# Reason: Phase 2 loaded patched chunk_00 via SBA (0x80001000=0x11223344).
# Hart 1 read this value from DDR via L2 into its private L1 D-cache.
# Phase 3 FLUSH64 only invalidates the SHARED L2; it does NOT touch Hart 1's L1 D-cache.
# If we use SBA (monitor WriteU32) for Phase 2.75, it goes directly to DDR,
# bypassing L1 coherency, so Hart 1's L1 D-cache still has 0x11223344 → stays polling forever.
# FIX: use a CPU write (set *(unsigned int*)) which goes through Hart 0's L1 D-cache
# → TileLink coherency → Probe sent to Hart 1's L1 D-cache → Hart 1's line INVALIDATED
# → Hart 1's next read of 0x80001000 is a L1 miss → L2 returns new value 0x6318972a ✓
# Phase 3 is already complete, so this dirty L2 line will NOT be incorrectly flushed back.
set *(unsigned int*)0x80001000 = 0x6318972a
echo [hart1-release] CPU write 0x80001000=0x6318972a: L1 Probe sent to Hart 1 (will detect in <1us, jump in 3s)\n

# ============================================================
# Phase 3.5: Resume Hart 1 via DMI WriteDMI
# ============================================================
# ROOT CAUSE FIX: 'monitor halt' halts BOTH harts. 'continue' only resumes Hart 0.
# Hart 1 stays in debug-halt forever → cannot respond to kernel IPI (MSIP[1]=1 pending, never consumed).
# FIX: Use DMI dmcontrol to select Hart 1 and set resumereq=1.
#   dmcontrol (addr 0x10):
#     bit 30 = resumereq, bits[15:6] = hartsello (hartsel=1 → bit6=1 = 0x40 in word)
#     bit 0  = dmactive
#   To resume Hart 1: 0x40000000 | 0x00000040 | 0x00000001 = 0x40000041
#   To clear resumereq: 0x00000040 | 0x00000001 = 0x00000041
#   To select back to Hart 0: 0x00000001
# After resume, Hart 1 runs sdboot → detects sentinel 0x6318972a → delay_ms(3000) →
# jumps to 0x80000000 → OpenSBI: lottery fails → _wait_for_boot_hart (polls _boot_status=2) →
# _start_warm → sbi_hsm_hart_wait WFI (STOPPED state, waiting for kernel IPI)
# Timeline: Hart 1 needs ~3-4s to reach WFI. Kernel brings up CPU1 ~30-60s after Hart 0 boot. ✓
python
import gdb, time as _time

gdb.write("\n=== Phase 3.5: Resume Hart 1 via DMI ===\n")
try:
    out0 = gdb.execute("monitor ReadDMI 11", to_string=True).strip()
    gdb.write(f"[hart1-dmi] dmstatus before: {out0}\n")

    # Select Hart 1 + resumereq=1 + dmactive=1
    gdb.execute("monitor WriteDMI 10 40000041")
    _time.sleep(0.1)
    # Clear resumereq (keep hartsel=1 to read dmstatus)
    gdb.execute("monitor WriteDMI 10 00000041")
    _time.sleep(0.1)

    out1 = gdb.execute("monitor ReadDMI 11", to_string=True).strip()
    gdb.write(f"[hart1-dmi] dmstatus after: {out1}\n")

    # Select back to Hart 0
    gdb.execute("monitor WriteDMI 10 00000001")
    gdb.write("[hart1-dmi] Hart 1 RESUMED. Running sdboot → 3s → OpenSBI warmboot → sbi_hsm_hart_wait WFI\n")
    gdb.write("[hart1-dmi] Hart 0 selected. Continuing Phase 4...\n")
except Exception as _e:
    gdb.write(f"[hart1-dmi] WARNING: DMI resume failed: {_e}\n")
    gdb.write("[hart1-dmi] Continuing anyway (Hart 1 may not participate in SMP)\n")
end

# Verify SBA write integrity
echo [verify] Checking SBA write integrity...\n
python
import gdb
import struct

def read_u32(addr):
    return int(gdb.parse_and_eval(f"*(unsigned int*)0x{addr:x}"))

fw_path = "/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin"
fw_data = open(fw_path, "rb").read()
cpio_off = fw_data.find(b"070701")
if cpio_off < 0:
    gdb.write("[FAIL] Could not find CPIO magic in fw_payload.bin\n")
    cpio_pa = None
else:
    cpio_pa = 0x80000000 + cpio_off
    gdb.write(f"[verify] First CPIO header in fw_payload.bin: off=0x{cpio_off:x} pa=0x{cpio_pa:x}\n")

if cpio_pa is not None:
    cpio_w0 = read_u32(cpio_pa)
    cpio_w1 = read_u32(cpio_pa + 4)
    gdb.write(f"[verify] Initramfs magic @ 0x{cpio_pa:x}: 0x{cpio_w0:08x} 0x{cpio_w1:08x}\n")
    if cpio_w0 == 0x37303730 and (cpio_w1 & 0xFFFF) == 0x3130:
        gdb.write("[verify] Initramfs magic: OK (cpio 070701)\n")
    else:
        gdb.write("[FAIL] Initramfs magic MISMATCH at derived CPIO location\n")

linux_w0 = read_u32(0x80200000)
if linux_w0 == 0x106f5a4d:
    gdb.write("[verify] Linux _start: OK\n")
else:
    gdb.write(f"[FAIL] Linux _start: 0x{linux_w0:08x} (expected 0x106f5a4d)\n")

osbi_w0 = read_u32(0x80000000)
if osbi_w0 == 0x0e976f05:
    gdb.write("[verify] OpenSBI entry: OK\n")
else:
    gdb.write(f"[FAIL] OpenSBI entry: 0x{osbi_w0:08x} (expected 0x0e976f05)\n")

spots = [
    0x0, 0x10000, 0x40000, 0x80000, 0x100000, 0x200000, 0x400000,
    0x600000, 0x80f1a8, 0x80f200, 0x900000, 0xa00000, 0xb00000,
    0xc00000, 0xec0000, 0xec3200,
]
mismatches = 0
for off in spots:
    if off + 4 > len(fw_data):
        continue
    expected = struct.unpack("<I", fw_data[off:off + 4])[0]
    actual = read_u32(0x80000000 + off)
    if actual != expected:
        gdb.write(
            f"[FAIL] Mismatch @ 0x{0x80000000 + off:08x}: got 0x{actual:08x} expected 0x{expected:08x}\n"
        )
        mismatches += 1
gdb.write(f"[verify] Spot-check: {len(spots)} locations, {mismatches} mismatches\n")
end


# ============================================================
# Phase 4: fence.i
# ============================================================
echo \n=== Phase 4: fence.i ===\n

set *(unsigned int*)0x80038100 = 0x0000100f
set *(unsigned short*)0x80038104 = 0x9002
if $skip_l2 == 0
set *(unsigned long long*)0x2010200 = 0x80038100
else
echo [L2flush] Skipped Phase 4 trampoline flush for no-L2 config\n
end
set $pc = 0x80038100
stepi
echo [ok] fence.i\n

# ============================================================
# Phase 5: Boot OpenSBI -> mret -> Linux _start
# ============================================================
echo \n=== Phase 5: Boot to Linux _start ===\n

set $a0 = 0
set $a1 = 0x84000000
set $a2 = 0
set $pc = 0x80000000

delete breakpoints
hbreak *0x8000b2b2
echo [boot] Running OpenSBI to mret...\n
continue

python
import gdb, re, time

pc = int(gdb.parse_and_eval("$pc"))
if pc != 0x8000b2b2:
    gdb.write(f"\n[FAIL] Expected mret at 0x8000b2b2, got 0x{pc:x}\n")
    gdb.execute("info reg pc ra sp a0 a1 a2")
    gdb.execute("x/8i $pc")
    raise gdb.GdbError("OpenSBI did not reach mret")

gdb.write("[OK] OpenSBI reached mret\n")
gdb.execute("delete breakpoints")

a1_val = int(gdb.parse_and_eval("$a1"))
gdb.write(f"[dtb] a1 from OpenSBI = 0x{a1_val:x}\n")
try:
    dtb_magic = int(gdb.parse_and_eval(f"*(unsigned int*)0x{a1_val:x}"))
    gdb.write(f"[dtb] DTB magic at a1: 0x{dtb_magic:08x}")
    if dtb_magic == 0xedfe0dd0:
        gdb.write(" (valid)\n")
    else:
        gdb.write(" (INVALID!)\n")
except Exception as err:
    gdb.write(f"[dtb] DTB probe failed: {err}\n")

gdb.execute("set $a1 = 0x84000000")
gdb.write("[dtb] Redirected a1 -> 0x84000000 for external DTB\n")

gdb.execute("delete breakpoints")

gdb.write("\n=== Phase 5.5: Pre-boot UART IE disable ===\n")
# Clear UART IE register to prevent probe race crash (request_irq before uart_add_one_port)
# UART base = 0x64000000, IE register offset = 0x10
gdb.execute("monitor WriteU32 0x64000010 0x00000000")
gdb.write("[uart] Cleared UART IE @ 0x64000010 -> 0x0 (prevent probe race)\n")

# NOTE: Phase 5.5 sentinel UNLOCK removed (fix8).
# Hart 1 (BootROM) detects payload from 0x80001000=0x6318972a (original fw_payload value),
# jumps to 0x80000000, loses coldboot race to Hart 0, and enters OpenSBI warmboot WFI.
# This is the correct OpenSBI SMP flow. No sentinel manipulation needed.

# === CRITICAL: Clear dcsr ebreak/step bits BEFORE monitor go ===
# dcsr.ebreakm(15), ebreaks(13), ebreaku(12), step(2) must be 0 before running
gdb.write("\n=== Phase 5.6: Clear dcsr ebreak/step bits (pre-run) ===\n")
read_out2 = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
gdb.write(f"[dcsr-pre] {read_out2.strip()}\n")
m2 = re.search(r'(?:0x)?([0-9A-Fa-f]{8})', read_out2)
if m2:
    old_dcsr2 = int(m2.group(1), 16)
    DEBUG_RESUME_MASK = (1 << 15) | (1 << 13) | (1 << 12) | (1 << 2)
    new_dcsr2 = old_dcsr2 & ~DEBUG_RESUME_MASK
    gdb.write(f"[dcsr-pre] 0x{old_dcsr2:08X} -> 0x{new_dcsr2:08X}\n")
    gdb.execute(f"monitor WriteCSR 0x7b0 0x{new_dcsr2:08X}")
    gdb.write("[dcsr-pre] ebreak/step bits cleared\n")

gdb.write("\n=== Phase 5b: Leave mret path (timed go/halt) ===\n")
start_pc = int(gdb.parse_and_eval("$pc"))
pc2 = start_pc
gdb.write(f"[boot] Starting timed go/halt from pc=0x{start_pc:x}\n")

for i in range(20):
    gdb.execute("monitor go")
    time.sleep(0.2)
    gdb.execute("monitor halt")
    pc2 = int(gdb.parse_and_eval("$pc"))
    gdb.write(f"[boot] probe {i + 1}/20: pc=0x{pc2:x}\n")
    if pc2 != start_pc:
        break

if pc2 == start_pc:
    gdb.write("[WARN] PC did not advance from mret window after timed go/halt probes\n")
elif pc2 == 0x80200000:
    gdb.write(f"[OK] Linux _start reached: pc=0x{pc2:x}\n")
elif 0x80200000 <= pc2 < 0x90000000:
    gdb.write(f"[OK] Linux execution observed past entry: pc=0x{pc2:x}\n")
else:
    gdb.write(f"[WARN] Unexpected PC after mret transition: 0x{pc2:x}\n")

gdb.write("\n=== Phase 6: Clear dcsr ebreak bits ===\n")

read_out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
gdb.write(f"[dcsr] Before: {read_out.strip()}\n")

m = re.search(r'(?:0x)?([0-9A-Fa-f]{8})', read_out)
if not m:
    raise gdb.GdbError(f"Cannot parse dcsr from: {read_out.strip()}")
old_dcsr = int(m.group(1), 16)

DEBUG_RESUME_MASK = (1 << 15) | (1 << 13) | (1 << 12) | (1 << 2)
new_dcsr = old_dcsr & ~DEBUG_RESUME_MASK
gdb.write(f"[dcsr] old=0x{old_dcsr:08X} -> new=0x{new_dcsr:08X} (cleared bits 15,13,12,2)\n")

gdb.execute(f"monitor WriteCSR 0x7b0 0x{new_dcsr:08X}")
verify_out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
gdb.write(f"[dcsr] After:  {verify_out.strip()}\n")
gdb.write("[OK] dcsr ebreak bits cleared\n")

try:
    pc_before_run = int(gdb.parse_and_eval("$pc"))
    if pc_before_run == 0x80200000:
        gdb.write("[boot] Advancing past Linux entry stub with stepi x2...\n")
        gdb.execute("stepi")
        gdb.execute("stepi")
        pc_after_run = int(gdb.parse_and_eval("$pc"))
        gdb.write(f"[boot] PC after entry stepi = 0x{pc_after_run:x}\n")
except Exception as err:
    gdb.write(f"[boot] Entry stepi workaround failed: {err}\n")
end


# ==========================================================
# Phase 7: Launch kernel + auto-dump klog after timeout
# ==========================================================
python
import os, time, gdb

KERNEL_RUN_SECS = int(os.environ.get("KERNEL_RUN_SECS", "300"))

gdb.write(f"\n=== Phase 7: Launch kernel (run {KERNEL_RUN_SECS}s then dump klog) ===\n")
gdb.execute("delete breakpoints")

gdb.write("[triggers] Clearing hardware trigger CSRs...\n")
for trig_idx in range(2):
    gdb.execute(f"monitor WriteCSR 0x7a0 {trig_idx}")
    gdb.execute("monitor WriteCSR 0x7a1 0")
    gdb.execute("monitor WriteCSR 0x7a2 0")
gdb.write("[OK] Hardware triggers cleared (tselect 0 and 1)\n")

# ============================================================
# Phase 7.1: Resume Hart 1 directly (bypass sdboot 3s delay)
# ROOT CAUSE: 'monitor halt' at script start halts BOTH harts in sdboot.
# GDB 'continue' only resumes hart 0 (hartsel=0 default in J-Link).
# Hart 1 stays debug-halted → kernel IPI (MSIP[1]) is never consumed.
# FIX: Use WriteDMI to select hartsel=1, set Hart 1's DPC = 0x80000000
#      (OpenSBI entry), then resume. This bypasses sdboot's 3s delay entirely.
#      Hart 1 goes through OpenSBI warmboot WFI before kernel starts. ✓
# ============================================================
gdb.write("\n=== Phase 7.1: Hart 1 direct boot (WriteDMI bypass sdboot) ===\n")
_hart1_ok = False
try:
    # Select Hart 1: dmcontrol[25:16]=1 (hartsel=1), dmcontrol[0]=1 (dmactive)
    gdb.execute("monitor WriteDMI 0x10 0x00010001")
    time.sleep(0.05)
    # Set Hart 1's DPC to OpenSBI entry (0x80000000), bypassing sdboot 3s delay
    gdb.execute("monitor WriteCSR 0x7b1 0x80000000")
    gdb.write("[hart1-boot] Hart 1 DPC set to 0x80000000 (OpenSBI entry)\n")
    time.sleep(0.05)
    # Resume Hart 1: resumereq (bit[30]=1) + hartsel=1 + dmactive=1 = 0x40010001
    gdb.execute("monitor WriteDMI 0x10 0x40010001")
    time.sleep(0.05)
    # Clear resumereq (keep hartsel=1, dmactive=1)
    gdb.execute("monitor WriteDMI 0x10 0x00010001")
    time.sleep(0.05)
    # Restore hartsel=0 for Hart 0 operations
    gdb.execute("monitor WriteDMI 0x10 0x00000001")
    gdb.write("[hart1-boot] Hart 1 resumed at OpenSBI via WriteDMI ✓\n")
    _hart1_ok = True
    # Give Hart 1 time to reach sbi_hsm_hart_wait WFI before kernel starts
    time.sleep(0.5)
except Exception as _e:
    gdb.write(f"[hart1-boot] WriteDMI failed ({_e}), trying fallback...\n")

if not _hart1_ok:
    # Fallback: J-Link specific syntax (may not work)
    for _cmd in ["Go 1", "go 1", "ResumeHart 1"]:
        try:
            _out = gdb.execute(f"monitor {_cmd}", to_string=True).strip()
            gdb.write(f"[hart1-boot] monitor {_cmd}: '{_out}'\n")
            _hart1_ok = True
            break
        except Exception as _e2:
            gdb.write(f"[hart1-boot] monitor {_cmd}: {_e2}\n")
    if not _hart1_ok:
        gdb.write("[hart1-boot] WARNING: Hart 1 may not be resumed! SMP will fail.\n")
gdb.write(f"[hart1-boot] Hart 1 resume status: {'OK' if _hart1_ok else 'FAILED'}\n")
# Ensure hartsel=0 so Hart 0 dcsr is not disturbed
try:
    gdb.execute("monitor WriteDMI 0x10 0x00000001")
except Exception:
    pass

gdb.write(f"\n[boot] Launching kernel (async), will halt in {KERNEL_RUN_SECS}s...\n")
# CRITICAL: do NOT use 'monitor go' -- J-Link re-sets dcsr.ebreak bits on
# monitor go/halt, which re-traps the CPU on first instruction after mret.
# Use GDB 'continue' instead, which uses abstract command resume (not monitor go)
# and does not touch dcsr.ebreak.
# We use a hbreak at unreachable address 0xdeadbeef to keep GDB in connected
# running state, then interrupt after KERNEL_RUN_SECS.
gdb.execute("delete breakpoints")

import threading as _threading

def _halt_after_delay(secs, gdb_module):
    import time as _t
    _t.sleep(secs)
    try:
        import signal, os
        os.kill(os.getpid(), signal.SIGINT)
    except Exception:
        pass

_halt_thread = _threading.Thread(
    target=_halt_after_delay,
    args=(KERNEL_RUN_SECS, gdb),
    daemon=True
)
_halt_thread.start()

gdb.write("[boot] Kernel running (via GDB continue + SIGINT timer)...\n")
try:
    gdb.execute("continue")
except KeyboardInterrupt:
    pass
except gdb.error as _e:
    gdb.write(f"[boot] continue returned: {_e}\n")

gdb.write("[boot] Continue done.\n")
# Ensure CPU is halted after continue returns
try:
    gdb.execute("monitor halt")
except Exception:
    pass
time.sleep(1)

try:
    pc_test = int(gdb.parse_and_eval("$pc"))
    gdb.write(f"[boot] Target halted at PC = 0x{pc_test & 0xFFFFFFFFFFFFFFFF:016x}\n")
except Exception as err:
    gdb.write(f"[boot] PC read after halt failed: {err}\n")

# === Hart 1 diagnostic (SMP debug) ===
gdb.write("\n=== Hart 1 diagnostic ===\n")

import struct as _struct
def _rdw(pa, n):
    tmp = f"/tmp/_diag_rd_{pa:x}_{n}.bin"
    gdb.execute(f"dump binary memory {tmp} 0x{pa:x} 0x{pa+n:x}", to_string=True)
    with open(tmp, "rb") as f:
        return f.read()

# CLINT MSIP[0] @ 0x02000000, MSIP[1] @ 0x02000004
try:
    msip0 = _struct.unpack("<I", _rdw(0x02000000, 4))[0]
    msip1 = _struct.unpack("<I", _rdw(0x02000004, 4))[0]
    gdb.write(f"[hart1-diag] CLINT MSIP[0]=0x{msip0:08x}  MSIP[1]=0x{msip1:08x}  (1=IPI pending)\n")
except Exception as e:
    gdb.write(f"[hart1-diag] CLINT MSIP read failed: {e}\n")

# OpenSBI platform.hart_count @ 0x80020250 (u32)
try:
    hc = _struct.unpack("<I", _rdw(0x80020250, 4))[0]
    gdb.write(f"[hart1-diag] OpenSBI platform.hart_count = {hc}\n")
except Exception as e:
    gdb.write(f"[hart1-diag] hart_count read failed: {e}\n")

# generic_hart_index2id[] @ 0x8002dbf0
try:
    arr = _rdw(0x8002dbf0, 16)
    ids = _struct.unpack("<IIII", arr)
    gdb.write(f"[hart1-diag] generic_hart_index2id[0..3] = {ids}\n")
except Exception as e:
    gdb.write(f"[hart1-diag] hart_index2id read failed: {e}\n")

# Sentinel value at 0x80001000 (must be 0x6318972a if hart 1 was released)
try:
    sent = _struct.unpack("<I", _rdw(0x80001000, 4))[0]
    gdb.write(f"[hart1-diag] Sentinel @0x80001000 = 0x{sent:08x}  (0x6318972a=released)\n")
except Exception as e:
    gdb.write(f"[hart1-diag] sentinel read failed: {e}\n")

gdb.write("[hart1-diag] (Hart 1 thread not exposed by J-Link RISC-V driver)\n")
end


python
import gdb, re, os, struct, time, subprocess

gdb.write("\n=== Phase 8: Dump kernel log (same session) ===\n")

VMLINUX = "/root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux"
NM = "/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-nm"
RUN_TAG = os.environ.get("RUN_TAG", time.strftime("run_%Y%m%d_%H%M%S"))
KLOG_BIN = f"/tmp/klog_{RUN_TAG}.bin"
LOG_FILE = f"/tmp/boot_{RUN_TAG}.strings"
SYMBOL_CACHE = None

def load_symbols():
    global SYMBOL_CACHE
    if SYMBOL_CACHE is None:
        text = subprocess.check_output([NM, "-n", VMLINUX], text=True)
        SYMBOL_CACHE = {}
        for line in text.splitlines():
            parts = line.split()
            if len(parts) == 3:
                try:
                    SYMBOL_CACHE[parts[2]] = int(parts[0], 16)
                except ValueError:
                    pass
    return SYMBOL_CACHE

def lookup_symbol(name):
    return load_symbols().get(name)

def kernel_va_to_pa(addr):
    if addr is None:
        return None
    if 0xffffffd800000000 <= addr < 0xffffffd900000000:
        return addr - 0xffffffd800000000 + 0x80000000
    if addr >= 0xffffffff80000000:
        return (addr - 0xffffffff80000000 + 0x80200000) & 0xFFFFFFFFFFFFFFFF
    return addr

def read_pa_u32(pa):
    tmp = f"/tmp/_phase8_rd32_{pa:x}.bin"
    gdb.execute(f"dump binary memory {tmp} 0x{pa:x} 0x{pa + 4:x}", to_string=True)
    with open(tmp, "rb") as f:
        return struct.unpack("<I", f.read(4))[0]

def read_pa_u64(pa):
    tmp = f"/tmp/_phase8_rd64_{pa:x}.bin"
    gdb.execute(f"dump binary memory {tmp} 0x{pa:x} 0x{pa + 8:x}", to_string=True)
    with open(tmp, "rb") as f:
        return struct.unpack("<Q", f.read(8))[0]

def read_csr(name, csr_num):
    try:
        out = gdb.execute(f"monitor ReadCSR 0x{csr_num:x}", to_string=True)
        m = re.search(r'(?:0x)?([0-9A-Fa-f]{1,16})', out)
        if m:
            val = int(m.group(1), 16)
            gdb.write(f"[state] {name} = 0x{val & 0xFFFFFFFFFFFFFFFF:016x}\n")
            return val
    except Exception as err:
        gdb.write(f"[state] {name} read failed: {err}\n")
    return None

try:
    pc = int(gdb.parse_and_eval("$pc"))
    gdb.write(f"[state] PC = 0x{pc & 0xFFFFFFFFFFFFFFFF:016x}\n")
except Exception:
    gdb.write("[state] PC read failed\n")

satp_val = read_csr("satp", 0x180)
read_csr("scause", 0x142)
read_csr("sepc", 0x141)
read_csr("stval", 0x143)
read_csr("mcause", 0x342)
read_csr("mepc", 0x341)
read_csr("mtval", 0x343)
read_csr("dcsr", 0x7b0)
read_csr("dpc", 0x7b1)

log_buf_len_va = lookup_symbol("log_buf_len")
log_buf_va_var = lookup_symbol("log_buf")
static_log_buf_va = lookup_symbol("__log_buf")

if log_buf_len_va is None or log_buf_va_var is None or static_log_buf_va is None:
    raise gdb.GdbError("Could not resolve printk ring symbols from vmlinux")

log_buf_len_pa = kernel_va_to_pa(log_buf_len_va)
log_buf_var_pa = kernel_va_to_pa(log_buf_va_var)
static_log_buf_pa = kernel_va_to_pa(static_log_buf_va)

log_buf_len = read_pa_u32(log_buf_len_pa)
log_buf_ptr = read_pa_u64(log_buf_var_pa)
log_buf_pa = kernel_va_to_pa(log_buf_ptr)

gdb.write(f"[klog] log_buf_len VA=0x{log_buf_len_va:016x} PA=0x{log_buf_len_pa:08x} -> 0x{log_buf_len:x}\n")
gdb.write(f"[klog] log_buf     VA=0x{log_buf_va_var:016x} PA=0x{log_buf_var_pa:08x} -> 0x{log_buf_ptr:016x}\n")
gdb.write(f"[klog] __log_buf   VA=0x{static_log_buf_va:016x} PA=0x{static_log_buf_pa:08x}\n")

dump_pa = log_buf_pa
if not (0x80000000 <= dump_pa < 0x100000000):
    gdb.write(f"[klog] log_buf PA 0x{dump_pa:016x} out of DDR range, falling back to __log_buf\n")
    dump_pa = static_log_buf_pa

if not (0 < log_buf_len <= 0x200000):
    gdb.write(f"[klog] log_buf_len 0x{log_buf_len:x} invalid, falling back to 0x20000\n")
    log_buf_len = 0x20000

dump_len = min(log_buf_len, 0x200000)

gdb.write(f"[dump] Dumping {dump_len} bytes from PA 0x{dump_pa:x} -> {KLOG_BIN}\n")
gdb.execute(f"dump binary memory {KLOG_BIN} 0x{dump_pa:x} 0x{dump_pa + dump_len:x}")
gdb.write(f"[dump] Saved to {KLOG_BIN}\n")
gdb.execute(f"dump binary memory /tmp/klog_latest.bin 0x{dump_pa:x} 0x{dump_pa + dump_len:x}")

try:
    data = open(KLOG_BIN, "rb").read()
    strings = re.findall(rb'[\x20-\x7e]{8,}', data)
    gdb.write(f"\n[strings] Found {len(strings)} strings in klog\n")

    milestones = {
        "clocksource": False,
        "Freeing unused": False,
        "Run /init": False,
        "init_pipe_fs": False,
        "populate_rootfs": False,
        "Kernel panic": False,
        "Oops": False,
        "invalid magic": False,
        "Welcome": False,
        "busybox": False,
        "/bin/sh": False,
        "sdhci": False,
        "mmc0": False,
        "mmcblk": False,
        "arasan": False,
        "smp: Brought up 2": False,
        "Brought up 2 nodes, 2 CPUs": False,
        "CPU1: thread": False,
    }

    with open(LOG_FILE, "w") as f:
        for i, s in enumerate(strings):
            line = s.decode("ascii", errors="replace")
            f.write(f"{i:4d}: {line}\n")
            for key in milestones:
                if key.lower() in line.lower():
                    milestones[key] = True
            if i < 60 or i >= len(strings) - 20:
                gdb.write(f"  {i:4d}: {line[:120]}\n")
            elif i == 60:
                gdb.write(f"  ... ({len(strings) - 80} more strings) ...\n")

    gdb.write("\n[milestones]\n")
    for key, hit in milestones.items():
        status = "YES" if hit else "no"
        gdb.write(f"  {key:20s}: {status}\n")

    gdb.write(f"\n[files] klog binary: {KLOG_BIN}\n")
    gdb.write(f"[files] klog strings: {LOG_FILE}\n")

except Exception as err:
    gdb.write(f"[error] String extraction failed: {err}\n")

try:
    fw_data = open("/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin", "rb").read()
    cpio_off = fw_data.find(b"070701")
    if cpio_off >= 0:
        cpio_pa = 0x80000000 + cpio_off
        cpio_w0 = int(gdb.parse_and_eval(f"*(unsigned int*)0x{cpio_pa:x}"))
        cpio_w1 = int(gdb.parse_and_eval(f"*(unsigned int*)0x{cpio_pa + 4:x}"))
        expected_cpio = (cpio_w0 == 0x37303730 and (cpio_w1 & 0xFFFF) == 0x3130)
        gdb.write(f"\n[post-check] Initramfs magic @ PA 0x{cpio_pa:x}: 0x{cpio_w0:08x} 0x{cpio_w1:08x}")
        gdb.write(f" ({'OK' if expected_cpio else 'CORRUPTED!'})\n")
    else:
        gdb.write("\n[post-check] Could not find CPIO header in fw_payload.bin\n")
except Exception as err:
    gdb.write(f"[post-check] Initramfs read failed: {err}\n")

# ---------------------------------------------------------------
# stage_mark region dump @ PA 0x8F000000 (256 bytes)
# /init writes a single u64 per mark_stage() call (overwrite semantics).
# Last-written value tells us which stage /init reached before halt.
# ---------------------------------------------------------------
try:
    STAGE_PA = 0x8F000000
    STAGE_LEN = 0x100
    stage_bin = f"/tmp/stage_{RUN_TAG}.bin"
    gdb.execute(f"dump binary memory {stage_bin} 0x{STAGE_PA:x} 0x{STAGE_PA + STAGE_LEN:x}")
    data = open(stage_bin, "rb").read()
    gdb.write(f"\n[stage_mark] dumped {len(data)} bytes from PA 0x{STAGE_PA:x} -> {stage_bin}\n")
    # First u64 = most recent stage written by /sbin/stage_mark
    if len(data) >= 8:
        v = int.from_bytes(data[0:8], "little")
        tag = "STGE" if ((v >> 32) & 0xFFFFFFFF) == 0x53544745 else "----"
        sub = v & 0xFFFFFFFF
        gdb.write(f"[stage_mark] last stage u64 = 0x{v:016x} (tag={tag}, sub=0x{sub:08x})\n")
    # Hex + ASCII dump of first 128 bytes
    gdb.write("[stage_mark] first 128 bytes (hex + ASCII):\n")
    for off in range(0, min(128, len(data)), 16):
        chunk = data[off:off+16]
        hx = " ".join(f"{b:02x}" for b in chunk)
        asc = "".join(chr(b) if 0x20 <= b < 0x7f else "." for b in chunk)
        gdb.write(f"  {off:04x}: {hx:<48s}  |{asc}|\n")
except Exception as err:
    gdb.write(f"[stage_mark] dump failed: {err}\n")

gdb.write("\n=== Boot + dump complete ===\n")
end
