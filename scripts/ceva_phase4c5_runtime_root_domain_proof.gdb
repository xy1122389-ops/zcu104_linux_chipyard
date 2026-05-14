set pagination off
set confirm off
set breakpoint auto-hw off
set remotetimeout 120

python
import os, gdb
host = os.environ.get("JLINK_HOST", "127.0.0.1")
port = int(os.environ.get("JLINK_PORT", "3333"))
chunk0 = os.environ.get("PHASE4C5_FW_CHUNK0", "/tmp/phase4c5_fw_chunk_00.bin")
dtb_path = os.environ.get("PHASE4C5_DTB", "/root/chipyard/fpga/linux-bringup/dtb/chipyard-zcu104-fedora.dtb")
fw_elf = os.environ.get("PHASE4C5_FW_ELF", "/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf")

gdb.write(f"[init] Connecting to J-Link {host}:{port}...\n")
gdb.execute(f"target remote {host}:{port}")
gdb.execute("monitor halt")
gdb.write("[init] Halted target\n")
gdb.execute("monitor WriteCSR 0x180 0")
gdb.execute("monitor WriteCSR 0x7b0 0x4000F0C3")
gdb.write("[init] Reset satp and dcsr to known boot state\n")
gdb.write(f"[load] Restoring first fw_payload chunk {chunk0} at 0x80000000\n")
gdb.execute(f"restore {chunk0} binary 0x80000000")
gdb.write(f"[load] Restoring DTB {dtb_path} at 0x84000000\n")
gdb.execute(f"restore {dtb_path} binary 0x84000000")
gdb.execute(f"add-symbol-file {fw_elf} 0x80000000", to_string=True)
gdb.write("[init] Added fw_payload.elf symbols after restore\n")
end

set $pc = 0x80000000
set $a0 = 0
set $a1 = 0x84000000

hbreak generic_domains_init

echo [check] continuing to generic_domains_init entry\n
continue
python
pc = int(gdb.parse_and_eval("(unsigned long long)$pc"))
gdb.write(f"[hit] generic_domains_init pc=0x{pc:016X}\n")
try:
    count_before = int(gdb.parse_and_eval("(unsigned int)root_memregs_count"))
    gdb.write(f"[root] root_memregs_count before={count_before}\n")
except Exception as e:
    gdb.write(f"[root] failed to read root_memregs_count before: {e}\n")
end

set $return_pc = $ra
hbreak *$return_pc

echo [check] continuing to generic_domains_init return site\n
continue
python
RES_START = 0x8FBE0000
RES_END = 0x8FEFFFFF
EXPECTED_FLAGS = 0x47

pc = int(gdb.parse_and_eval("(unsigned long long)$pc"))
gdb.write(f"[ret] post-carveout pc=0x{pc:016X}\n")

count = int(gdb.parse_and_eval("(unsigned int)root_memregs_count"))
gdb.write(f"[root] root_memregs_count after={count}\n")

regions_ptr = gdb.parse_and_eval("root.regions")
match_count = 0
for index in range(count):
    region = (regions_ptr + index).dereference()
    order = int(region['order'])
    base = int(region['base'])
    flags = int(region['flags'])
    if order >= 64:
        end = 0xFFFFFFFFFFFFFFFF
    else:
        end = base + ((1 << order) - 1)
    overlaps = not (end < RES_START or RES_END < base)
    gdb.write(f"[root] region[{index}] base=0x{base:016X} end=0x{end:016X} order={order} flags=0x{flags:016X}")
    if overlaps:
        gdb.write(" overlap=CEVA_RESERVED")
        if flags == EXPECTED_FLAGS:
            gdb.write(" flags_ok=1")
        else:
            gdb.write(" flags_ok=0")
        match_count += 1
    gdb.write("\n")

gdb.write(f"[root] reserved_overlap_regions={match_count}\n")
end

monitor halt
detach
quit