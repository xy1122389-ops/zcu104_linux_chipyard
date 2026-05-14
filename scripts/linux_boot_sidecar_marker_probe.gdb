# Phase 3B-H3 sidecar marker load proof.
# Build sidecar.bin before running this script. This script does not boot Linux.

set pagination off
set confirm off
set breakpoint auto-hw off
set remotetimeout 120

python
import os, struct, gdb

host = os.environ.get("JLINK_HOST", "127.0.0.1")
port = int(os.environ.get("JLINK_PORT", "3333"))
sidecar_elf = os.environ.get(
    "SIDECAR_ELF",
    "/root/chipyard/fpga/sidecar/ceva_bt52_sidecar/build/sidecar.elf",
)
sidecar_bin = os.environ.get(
    "SIDECAR_BIN",
    "/root/chipyard/fpga/sidecar/ceva_bt52_sidecar/build/sidecar.bin",
)
marker_base = int(os.environ.get("SIDECAR_MARKER_BASE", "0x8FBE0000"), 0)
image_base = int(os.environ.get("SIDECAR_IMAGE_BASE", "0x8FBF0000"), 0)
marker_size = int(os.environ.get("SIDECAR_MARKER_SIZE", "0x90"), 0)
dump_path = os.environ.get("SIDECAR_MARKER_DUMP", "/tmp/phase3b_h3_sidecar_marker.bin")

BOOT_MAGIC = 0x53434452424F4F54
MAIN_ENTER = 0x534344524D41494E
LOOP_ALIVE = 0x53434452414C4956
SIDECAR_START = 0x5349444553545254
INGRESS_READY = 0x53494445494E4752

for path in (sidecar_elf, sidecar_bin):
    if not os.path.exists(path):
        raise RuntimeError(f"missing sidecar artifact: {path}")

gdb.write(f"[h3] Connecting to J-Link {host}:{port}\n")
gdb.execute(f"target remote {host}:{port}")
gdb.execute("monitor halt")
gdb.write("[h3] Halted target\n")

gdb.execute(f"add-symbol-file {sidecar_elf} 0x{image_base:x}", to_string=True)
gdb.write(f"[h3] Loaded sidecar symbols at 0x{image_base:08x}\n")

zero_path = "/tmp/phase3b_h3_zero_marker.bin"
with open(zero_path, "wb") as fh:
    fh.write(b"\x00" * marker_size)

gdb.write(f"[h3] Clearing marker page 0x{marker_base:08x}..0x{marker_base + marker_size:08x}\n")
gdb.execute(f"restore {zero_path} binary 0x{marker_base:x}")

gdb.write(f"[h3] Restoring sidecar image to 0x{image_base:08x}\n")
gdb.execute(f"restore {sidecar_bin} binary 0x{image_base:x}")
gdb.execute("monitor WriteCSR 0x180 0")
gdb.execute(f"set $pc = 0x{image_base:x}")

gdb.write("[h3] Stepping sidecar skeleton\n")
for _ in range(256):
    gdb.execute("stepi", to_string=True)

gdb.write(f"[h3] Dumping marker page to {dump_path}\n")
gdb.execute(f"dump binary memory {dump_path} 0x{marker_base:x} 0x{marker_base + marker_size:x}")

with open(dump_path, "rb") as fh:
    data = fh.read()

def slot(offset):
    return struct.unpack_from("<Q", data, offset)[0]

checks = [
    (0x00, "SIDECAR_BOOT_MAGIC", BOOT_MAGIC),
    (0x08, "SIDECAR_START", SIDECAR_START),
    (0x10, "SIDECAR_MAIN_ENTER", MAIN_ENTER),
    (0x28, "SIDECAR_INGRESS_READY", INGRESS_READY),
    (0x78, "SIDECAR_LOOP_ALIVE", LOOP_ALIVE),
]

failed = False
for offset, label, expected in checks:
    value = slot(offset)
    gdb.write(f"[h3] {label}@+0x{offset:02x}=0x{value:016X}\n")
    if value != expected:
        failed = True

loop_seq = slot(0x68)
gdb.write(f"[h3] SIDECAR_LOOP_SEQ@+0x68=0x{loop_seq:016X}\n")

if failed:
    raise RuntimeError("H3 marker proof failed")

gdb.write("[h3] H3_MARKER_PROOF=PASS\n")
end

detach
quit
