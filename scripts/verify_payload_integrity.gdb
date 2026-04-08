set pagination off
set confirm off
set remotetimeout 600

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import gdb, os, time
host = os.environ.get("JLINK_HOST", "172.19.128.1")
port = int(os.environ.get("JLINK_PORT", "2331"))
gdb.write(f"[info] Connecting to J-Link at {host}:{port}\n")
for attempt in range(1, 4):
    try:
        gdb.execute(f"target remote {host}:{port}")
        gdb.write(f"[info] Connected on attempt {attempt}\n")
        break
    except gdb.error as err:
        if attempt == 3:
            raise
        time.sleep(2)
end

monitor halt
monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

echo \n=== Load payload with interleaved copyback ===\n
python
import os, gdb, time

COPYBACK_ADDR = 0x80F00000
SUB_CHUNK = 256 * 1024

# Write copyback routine
instrs = [
    (COPYBACK_ADDR + 0x00, 0x0000100f),
    (COPYBACK_ADDR + 0x04, 0x00053283),
    (COPYBACK_ADDR + 0x08, 0x00553023),
    (COPYBACK_ADDR + 0x0C, 0x04050513),
    (COPYBACK_ADDR + 0x10, 0xFEB54AE3),
    (COPYBACK_ADDR + 0x14, 0x00100073),
]
for addr, val in instrs:
    gdb.execute(f"set *(unsigned int*)0x{addr:x} = 0x{val:08x}")

# Copyback the routine itself
gdb.execute(f"set $a0 = 0x{COPYBACK_ADDR:x}")
gdb.execute(f"set $a1 = 0x{COPYBACK_ADDR + 64:x}")
gdb.execute(f"set $pc = 0x{COPYBACK_ADDR:x}")
gdb.execute(f"hbreak *0x{COPYBACK_ADDR + 0x14:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")

first_copyback = [True]
def run_copyback(start, end_aligned):
    entry = COPYBACK_ADDR if first_copyback[0] else COPYBACK_ADDR + 4
    first_copyback[0] = False
    gdb.execute(f"set $a0 = 0x{start:x}")
    gdb.execute(f"set $a1 = 0x{end_aligned:x}")
    gdb.execute(f"set $pc = 0x{entry:x}")
    gdb.execute(f"hbreak *0x{COPYBACK_ADDR + 0x14:x}")
    gdb.execute("continue")
    gdb.execute("delete breakpoints")

chunk_dir = "/tmp/fw_chunks_new"
base_addr = 0x80000000
chunk_size = 4194304
chunks = sorted([f for f in os.listdir(chunk_dir) if f.startswith("chunk_") and f.endswith(".bin")])

t_global = time.time()
sub_idx = 0
total_sub = 0
for f in chunks:
    total_sub += (os.path.getsize(os.path.join(chunk_dir, f)) + SUB_CHUNK - 1) // SUB_CHUNK

for i, fname in enumerate(chunks):
    fpath = os.path.join(chunk_dir, fname)
    fsize = os.path.getsize(fpath)
    file_base = base_addr + i * chunk_size
    for offset in range(0, fsize, SUB_CHUNK):
        sub_end = min(offset + SUB_CHUNK, fsize)
        sub_len = sub_end - offset
        mem_addr = file_base + offset
        sub_idx += 1
        gdb.execute(f"restore {fpath} binary 0x{file_base:x} 0x{offset:x} 0x{sub_end:x}")
        cb_end = (mem_addr + sub_len + 63) & ~63
        run_copyback(mem_addr, cb_end)
        if sub_idx % 16 == 0:
            gdb.write(f"[load+cb] {sub_idx}/{total_sub}\n")

gdb.write(f"[ok] Payload loaded+dirtied in {time.time()-t_global:.1f}s\n")
end

echo \n=== Dumping memory for verification (NO BOOT) ===\n
python
import gdb, os, time

# Dump 1MB regions at various offsets for spot-checking
regions = [
    (0x80000000, 0x80100000, "/tmp/verify_0x80000000.bin"),  # first 1MB
    (0x80200000, 0x80300000, "/tmp/verify_0x80200000.bin"),  # Linux _start region
    (0x8023b000, 0x8023c000, "/tmp/verify_0x8023b000.bin"),  # parse_args area
    (0x80800000, 0x80900000, "/tmp/verify_0x80800000.bin"),  # rodata region
    (0x80C00000, 0x80D00000, "/tmp/verify_0x80C00000.bin"),  # late data region
    (0x84000000, 0x84001069, "/tmp/verify_dtb.bin"),         # DTB
]

gdb.write("[dump] Starting memory reads for verification...\n")
for start, end, path in regions:
    t0 = time.time()
    gdb.execute(f"dump binary memory {path} 0x{start:x} 0x{end:x}")
    dt = time.time() - t0
    sz = end - start
    gdb.write(f"[dump] 0x{start:08x}-0x{end:08x} ({sz} bytes) -> {path} in {dt:.1f}s\n")

gdb.write("[ok] All regions dumped. Compare with originals.\n")
end

quit
