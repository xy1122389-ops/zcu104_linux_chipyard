## sba_write_verify.gdb — Phase 0: SBA write integrity verification
## Writes fw_payload.bin to DDR via SBA, then immediately reads back.
## Does NOT execute any CPU instructions — pure SBA write + read.
##
## Usage:
##   JLINK_PORT=2331 riscv64-unknown-elf-gdb -batch -x scripts/sba_write_verify.gdb

set pagination off
set confirm off
set breakpoint auto-hw off
set remotetimeout 600

# We don't strictly need symbols, but loading the ELF keeps GDB happy
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
        gdb.write(f"[warn] Attempt {attempt} failed: {err}\n")
        if attempt < 3:
            time.sleep(2)
if last_error is not None:
    raise last_error
end

monitor halt
echo [info] Target halted\n
info reg pc

# ============================================================
# Phase A: Restore fw_payload.bin via SBA (same as boot script)
# ============================================================
echo \n=== Phase A: Restore payload via SBA ===\n

python
import os, gdb, time

CHUNK_DIR = "/tmp/fw_chunks_new"
BASE_ADDR = 0x80000000
CHUNK_SIZE = 4194304  # 4 MB

chunks = sorted([f for f in os.listdir(CHUNK_DIR) if f.startswith("chunk_") and f.endswith(".bin")])
gdb.write(f"[restore] Loading fw_payload.bin in {len(chunks)} chunks...\n")

for i, fname in enumerate(chunks):
    addr = BASE_ADDR + i * CHUNK_SIZE
    fpath = os.path.join(CHUNK_DIR, fname)
    fsize = os.path.getsize(fpath)
    gdb.write(f"[restore {i+1}/{len(chunks)}] {fname} -> 0x{addr:08x} ({fsize} bytes)...\n")
    t0 = time.time()
    gdb.execute(f"restore {fpath} binary 0x{addr:x}")
    elapsed = time.time() - t0
    gdb.write(f"[restore {i+1}/{len(chunks)}] done in {elapsed:.1f}s\n")
    if i + 1 < len(chunks):
        time.sleep(0.2)

gdb.write("[ok] fw_payload.bin restore complete\n")
end

# Quick sanity: read first word at 0x80000000
python
import gdb
w0 = int(gdb.parse_and_eval("*(unsigned int*)0x80000000"))
gdb.write(f"[verify] First word at 0x80000000 = 0x{w0:08x}\n")
end

# ============================================================
# Phase B: Read back entire payload via SBA
# ============================================================
echo \n=== Phase B: Dump readback via SBA ===\n

python
import gdb, time

PAYLOAD_SIZE = 15477768  # exact size of fw_payload.bin
BASE_ADDR = 0x80000000
END_ADDR = BASE_ADDR + PAYLOAD_SIZE  # 0x80EC2C08
READBACK = "/tmp/payload_readback.bin"

gdb.write(f"[dump] Reading back 0x{BASE_ADDR:08x} - 0x{END_ADDR:08x} ({PAYLOAD_SIZE} bytes)...\n")
t0 = time.time()
gdb.execute(f"dump binary memory {READBACK} 0x{BASE_ADDR:x} 0x{END_ADDR:x}")
elapsed = time.time() - t0
gdb.write(f"[dump] Readback saved to {READBACK} in {elapsed:.1f}s\n")

import os
actual_size = os.path.getsize(READBACK)
gdb.write(f"[dump] Readback file size: {actual_size} bytes (expected {PAYLOAD_SIZE})\n")

if actual_size != PAYLOAD_SIZE:
    gdb.write(f"[WARN] Size mismatch! Expected {PAYLOAD_SIZE}, got {actual_size}\n")
else:
    gdb.write("[ok] Readback size matches\n")
end

echo \n=== SBA write verify complete ===\n
echo Run: python3 /root/chipyard/fpga/scripts/sba_write_verify_diff.py\n
quit
