## die_catch.gdb — Boot kernel, catch die() to read CLEAN pt_regs
## Usage: JLINK_PORT=12331 riscv64-unknown-linux-gnu-gdb -x scripts/die_catch.gdb
set pagination off
set confirm off
set breakpoint auto-hw off
set remotetimeout 600

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import gdb, os, time
host = os.environ.get("JLINK_HOST", "172.19.128.1")
port = int(os.environ.get("JLINK_PORT", "2331"))
for attempt in range(1, 4):
    try:
        gdb.execute(f"target remote {host}:{port}")
        gdb.write(f"[info] Connected on attempt {attempt}\n")
        break
    except gdb.error as err:
        gdb.write(f"[warn] Attempt {attempt}: {err}\n")
        if attempt < 3: time.sleep(2)
        else: raise
end

monitor halt

## Phase 1: Load payload
python
import gdb, os, time, glob, tempfile

chunk_dir = "/tmp/fw_chunks_allpatch"
dtb_path = "/root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux-withinit.dtb"
CB = 0x81200000
SENT = 0x81200014
CS = 256 * 1024

cb_code = bytes([
    0x73,0x00,0x50,0x10, 0x83,0x32,0x05,0x00, 0x23,0x30,0x55,0x00,
    0x13,0x05,0x85,0x00, 0xe3,0x4c,0xb5,0xfe, 0x23,0xb0,0x05,0x00,
    0x6f,0xf0,0x5f,0xfe,
])
with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as f:
    f.write(cb_code); tmp = f.name
gdb.execute(f"restore {tmp} binary {CB:#x}")
os.unlink(tmp)
gdb.execute(f"set $pc = {CB+4:#x}")
gdb.execute(f"set $a0 = {CB:#x}")
gdb.execute(f"set $a1 = {CB+len(cb_code):#x}")
gdb.execute(f"hbreak *{SENT:#x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.write("[ok] Copyback routine ready\n")

files = sorted(glob.glob(os.path.join(chunk_dir, "chunk_*.bin")))
total = sum(os.path.getsize(f) for f in files)
n = (total + CS - 1) // CS
gdb.write(f"[load] {total} bytes, {n} sub-chunks\n")

base = 0x80000000; idx = 0; t0 = time.time()
for fp in files:
    sz = os.path.getsize(fp); off = 0
    while off < sz:
        end = min(off + CS, sz); addr = base + off
        gdb.execute(f"restore {fp} binary {addr-off:#x} {off} {end}")
        gdb.execute(f"set $pc = {CB+4:#x}")
        gdb.execute(f"set $a0 = {addr:#x}")
        gdb.execute(f"set $a1 = {addr+(end-off):#x}")
        gdb.execute(f"set *((unsigned long*){SENT:#x}) = 1")
        gdb.execute(f"hbreak *{SENT:#x}")
        gdb.execute("continue")
        gdb.execute("delete breakpoints")
        idx += 1
        if idx % 8 == 0:
            gdb.write(f"[load] {idx}/{n} ({time.time()-t0:.0f}s)\n")
        off = end
    base += sz

gdb.write(f"[ok] Payload loaded in {time.time()-t0:.0f}s\n")

# DTB
gdb.execute(f"restore {dtb_path} binary 0x84000000")
dsz = os.path.getsize(dtb_path)
gdb.execute(f"set $pc = {CB+4:#x}")
gdb.execute(f"set $a0 = 0x84000000")
gdb.execute(f"set $a1 = {0x84000000+dsz:#x}")
gdb.execute(f"set *((unsigned long*){SENT:#x}) = 1")
gdb.execute(f"hbreak *{SENT:#x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.write("[ok] DTB loaded\n")
end

## Phase 2: Boot OpenSBI → mret → Linux
echo \n=== Phase 2: Boot ===\n
set $a0 = 0
set $a1 = 0x84000000
set $a2 = 0
set $pc = 0x80000000
delete breakpoints
hbreak *0x8000b1ca
echo [boot] OpenSBI running...\n
continue

python
import gdb, re
pc = int(gdb.parse_and_eval("$pc"))
if pc != 0x8000b1ca:
    gdb.write(f"[FAIL] mret not reached: PC=0x{pc:x}\n")
    raise gdb.GdbError("mret not reached")
gdb.write("[OK] mret reached\n")
gdb.execute("delete breakpoints")
gdb.execute("set $a1 = 0x84000000")
out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8})', out)
if m:
    old = int(m.group(1), 16)
    new = old & ~((1<<15)|(1<<13)|(1<<12)|(1<<2))
    gdb.execute(f"monitor WriteCSR 0x7b0 0x{new:08X}")
gdb.execute("hbreak *0x80200000")
gdb.execute("continue")
end

## Phase 3: Set hbreak on die(), continue, catch crash
echo \n=== Phase 3: Catch die() ===\n
symbol-file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux
delete breakpoints

python
import gdb

# die() is at 0xffffffff800052bc
# die(struct pt_regs *regs, const char *str)
# When we hit die(), a0 = pt_regs*, which is saved to s1
die_addr = 0xffffffff800052bc
gdb.execute(f"hbreak *0x{die_addr:x}")
gdb.write("[boot] Kernel running, waiting for die()...\n")
gdb.execute("continue")

pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"[die] Caught at PC=0x{pc:016x}\n")

if pc == die_addr:
    # a0 = pt_regs pointer (kernel VA, in S-mode so MMU should translate)
    pt_regs_va = int(gdb.parse_and_eval("$a0")) & 0xFFFFFFFFFFFFFFFF
    gdb.write(f"[die] pt_regs at VA 0x{pt_regs_va:016x}\n")
    gdb.write(f"[die] str (a1) = {gdb.execute('x/s $a1', to_string=True).strip()}\n")

    # Read pt_regs structure via kernel VA (should work in S-mode)
    # struct pt_regs offsets (each field is 8 bytes):
    reg_names = [
        (0,   "epc"),  (8,   "ra"),   (16,  "sp"),   (24,  "gp"),
        (32,  "tp"),   (40,  "t0"),   (48,  "t1"),   (56,  "t2"),
        (64,  "s0"),   (72,  "s1"),   (80,  "a0"),   (88,  "a1"),
        (96,  "a2"),   (104, "a3"),   (112, "a4"),    (120, "a5"),
        (128, "a6"),   (136, "a7"),   (144, "s2"),    (152, "s3"),
        (160, "s4"),   (168, "s5"),   (176, "s6"),    (184, "s7"),
        (192, "s8"),   (200, "s9"),   (208, "s10"),   (216, "s11"),
        (224, "t3"),   (232, "t4"),   (240, "t5"),    (248, "t6"),
        (256, "status"),(264,"badaddr"),(272,"cause"), (280, "orig_a0"),
    ]

    gdb.write("\n[pt_regs] CLEAN crash registers (direct from trap frame):\n")
    crash_regs = {}
    for offset, name in reg_names:
        try:
            val = int(gdb.parse_and_eval(f"*(unsigned long*)({pt_regs_va:#x} + {offset})")) & 0xFFFFFFFFFFFFFFFF
            crash_regs[name] = val
            gdb.write(f"  {name:8s} = 0x{val:016x}\n")
        except Exception as e:
            gdb.write(f"  {name:8s} = <read failed: {e}>\n")

    # Analysis
    epc = crash_regs.get("epc", 0)
    badaddr = crash_regs.get("badaddr", 0)
    cause = crash_regs.get("cause", 0)
    t2 = crash_regs.get("t2", 0)
    a0 = crash_regs.get("a0", 0)
    s1 = crash_regs.get("s1", 0)

    gdb.write(f"\n[crash] EPC=0x{epc:x} cause={cause} badaddr=0x{badaddr:x}\n")

    # Disassemble at crash EPC
    try:
        gdb.write(f"\n[disasm] At EPC 0x{epc:016x}:\n")
        gdb.execute(f"info symbol 0x{epc:x}")
        gdb.execute(f"x/8i 0x{epc:x}")
    except:
        gdb.write("  <unavailable>\n")

    # Read the string data at a0 and s1 (parameq's input)
    gdb.write(f"\n[strings] Reading string data at crash registers:\n")
    for name, addr in [("a0", a0), ("s1", s1), ("t2", t2)]:
        if addr > 0xffffffc000000000:
            try:
                data = b""
                for i in range(4):
                    v = int(gdb.parse_and_eval(f"*(unsigned long*)(0x{addr+i*8:x})")) & 0xFFFFFFFFFFFFFFFF
                    data += v.to_bytes(8, "little")
                nul = data.find(b'\x00')
                if nul >= 0:
                    s = data[:nul].decode("ascii", errors="replace")
                    gdb.write(f"  {name}(0x{addr:x}) = \"{s}\" [NUL at +{nul}]\n")
                else:
                    gdb.write(f"  {name}(0x{addr:x}) = {data[:32].hex()} [NO NUL!]\n")
            except Exception as e:
                gdb.write(f"  {name}(0x{addr:x}) = <cannot read: {e}>\n")
        elif addr >= 0x80000000 and addr < 0x100000000:
            gdb.write(f"  {name} = 0x{addr:x} (phys/OpenSBI range)\n")
        else:
            gdb.write(f"  {name} = 0x{addr:x} (not a kernel VA)\n")

    # Read saved_command_line via S-mode VA
    gdb.write(f"\n[cmdline] Reading saved_command_line:\n")
    try:
        ptr = int(gdb.parse_and_eval("*(unsigned long*)&saved_command_line")) & 0xFFFFFFFFFFFFFFFF
        gdb.write(f"  ptr = 0x{ptr:016x}\n")
        if ptr > 0xffffffc000000000:
            data = b""
            for i in range(16):
                v = int(gdb.parse_and_eval(f"*(unsigned long*)(0x{ptr+i*8:x})")) & 0xFFFFFFFFFFFFFFFF
                data += v.to_bytes(8, "little")
            nul = data.find(b'\x00')
            s = data[:nul].decode("ascii", errors="replace") if nul >= 0 else data[:128].decode("ascii", errors="replace")
            gdb.write(f"  cmdline = \"{s}\"\n")
    except Exception as e:
        gdb.write(f"  <error: {e}>\n")

else:
    gdb.write(f"[die] Did not stop at die(), PC=0x{pc:x}\n")
    gdb.execute("info reg pc ra sp")

gdb.write("\n[done] die_catch complete\n")
end

quit
