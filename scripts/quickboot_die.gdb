## quickboot_die.gdb — Boot from existing DDR data, catch die() for clean regs
set pagination off
set confirm off
set remotetimeout 60

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import gdb, os, time, re

host = os.environ.get("JLINK_HOST", "172.19.128.1")
port = int(os.environ.get("JLINK_PORT", "2331"))
for attempt in range(1, 4):
    try:
        gdb.execute(f"target remote {host}:{port}")
        break
    except gdb.error as err:
        if attempt < 3: time.sleep(2)
        else: raise

gdb.execute("monitor halt")
time.sleep(0.5)

# Verify DDR has valid payload (check first bytes)
w0 = int(gdb.parse_and_eval("*(unsigned int*)0x80000000")) & 0xFFFFFFFF
gdb.write(f"[verify] OpenSBI_w0=0x{w0:08x} (expect 0x0e976f05)\n")
if w0 != 0x0e976f05:
    gdb.write("[warn] Payload may be stale, need full reload\n")

# Full payload reload with copyback
import glob, tempfile
chunk_dir = "/tmp/fw_chunks_allpatch"
dtb_path = "/root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux-withinit.dtb"
CB = 0x81200000; SENT = 0x81200014; CS = 256*1024

cb_code = bytes([
    0x73,0x00,0x50,0x10, 0x83,0x32,0x05,0x00, 0x23,0x30,0x55,0x00,
    0x13,0x05,0x85,0x00, 0xe3,0x4c,0xb5,0xfe, 0x23,0xb0,0x05,0x00,
    0x6f,0xf0,0x5f,0xfe])
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

base = 0x80000000; idx = 0; t0_l = time.time()
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
            gdb.write(f"[load] {idx}/{n} ({time.time()-t0_l:.0f}s)\n")
        off = end
    base += sz
gdb.write(f"[ok] Payload loaded in {time.time()-t0_l:.0f}s\n")

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

# Set DCSR: prv=3 (M-mode), clear ebreak bits
gdb.execute("monitor WriteCSR 0x7b0 0x40000003")

# Boot OpenSBI
gdb.execute("set $a0 = 0")
gdb.execute("set $a1 = 0x84000000")
gdb.execute("set $a2 = 0")
gdb.execute("set $pc = 0x80000000")
gdb.execute("delete breakpoints")
gdb.execute("hbreak *0x8000b1ca")
gdb.write("[boot] Running OpenSBI...\n")
gdb.execute("continue")

pc = int(gdb.parse_and_eval("$pc"))
if pc != 0x8000b1ca:
    gdb.write(f"[FAIL] mret not reached: PC=0x{pc:x}\n")
    raise gdb.GdbError("mret fail")
gdb.write("[OK] mret reached\n")

# Clear DCSR for mret → S-mode
out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8})', out)
if m:
    old = int(m.group(1), 16)
    new = old & ~((1<<15)|(1<<13)|(1<<12)|(1<<2))
    gdb.execute(f"monitor WriteCSR 0x7b0 0x{new:08X}")

gdb.execute("delete breakpoints")
gdb.execute("set $a1 = 0x84000000")
gdb.execute("hbreak *0x80200000")
gdb.write("[boot] Continue to Linux _start...\n")
gdb.execute("continue")
pc = int(gdb.parse_and_eval("$pc"))
gdb.write(f"[boot] At Linux _start: PC=0x{pc:x}\n")

# Now set hbreak at die() and run kernel
gdb.execute("symbol-file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux")
gdb.execute("delete breakpoints")
gdb.execute("hbreak die")
gdb.write("[kernel] Running kernel, waiting for die()...\n")
gdb.execute("continue")

pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"\n[die] CAUGHT! PC=0x{pc:016x}\n")

# Read pt_regs from a0 (die's first argument)
pt = int(gdb.parse_and_eval("$a0")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"[die] pt_regs VA=0x{pt:016x}\n")

# Read die string from a1
try:
    s = gdb.execute("x/s $a1", to_string=True)
    gdb.write(f"[die] str = {s.strip()}\n")
except:
    gdb.write("[die] str = <cannot read>\n")

# Read all pt_regs fields
regs = [
    (0,"epc"),(8,"ra"),(16,"sp"),(24,"gp"),(32,"tp"),
    (40,"t0"),(48,"t1"),(56,"t2"),(64,"s0"),(72,"s1"),
    (80,"a0"),(88,"a1"),(96,"a2"),(104,"a3"),(112,"a4"),(120,"a5"),
    (128,"a6"),(136,"a7"),(144,"s2"),(152,"s3"),(160,"s4"),(168,"s5"),
    (176,"s6"),(184,"s7"),(192,"s8"),(200,"s9"),(208,"s10"),(216,"s11"),
    (224,"t3"),(232,"t4"),(240,"t5"),(248,"t6"),
    (256,"status"),(264,"badaddr"),(272,"cause"),(280,"orig_a0"),
]

gdb.write("\n====== CLEAN pt_regs (from trap frame, NO printk corruption) ======\n")
crash = {}
for off, name in regs:
    try:
        val = int(gdb.parse_and_eval(f"*(unsigned long*)({pt:#x}+{off})")) & 0xFFFFFFFFFFFFFFFF
        crash[name] = val
        gdb.write(f"  {name:8s} = 0x{val:016x}\n")
    except Exception as e:
        gdb.write(f"  {name:8s} = ERROR: {e}\n")

gdb.write("\n====== CRASH ANALYSIS ======\n")
epc = crash.get("epc", 0)
badaddr = crash.get("badaddr", 0) 
cause = crash.get("cause", 0)
t2 = crash.get("t2", 0)
a0_crash = crash.get("a0", 0)
s1_crash = crash.get("s1", 0)

is_int = (cause >> 63) & 1
code = cause & 0x7FFFFFFFFFFFFFFF
gdb.write(f"  EPC     = 0x{epc:016x}\n")
gdb.write(f"  cause   = {'interrupt' if is_int else 'exception'} code={code}\n")
gdb.write(f"  badaddr = 0x{badaddr:016x}\n")
gdb.write(f"  t2      = 0x{t2:016x}  (aligned ptr in strlen)\n")
gdb.write(f"  a0      = 0x{a0_crash:016x}  (strlen input = string ptr)\n")
gdb.write(f"  s1      = 0x{s1_crash:016x}  (parameq saved input)\n")

# Disassemble at EPC
try:
    gdb.write(f"\n[disasm] At EPC:\n")
    gdb.execute(f"info symbol 0x{epc:x}")
    gdb.execute(f"x/4i 0x{epc:x}")
except:
    pass

# Read string data at crash registers
gdb.write(f"\n====== STRING DATA AT CRASH REGISTERS ======\n")
for name, addr in [("a0", a0_crash), ("s1", s1_crash), ("t2", t2)]:
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
                gdb.write(f"  {name}(0x{addr:x}) hex = {data[:32].hex()} [NO NUL in 32B!]\n")
        except Exception as e:
            gdb.write(f"  {name}(0x{addr:x}) = CANNOT READ: {e}\n")
    elif addr == 0:
        gdb.write(f"  {name} = NULL\n")
    else:
        gdb.write(f"  {name} = 0x{addr:016x} (not a kernel VA)\n")

# Also read saved_command_line
try:
    ptr = int(gdb.parse_and_eval("*(unsigned long*)&saved_command_line")) & 0xFFFFFFFFFFFFFFFF
    if ptr > 0xffffffc000000000:
        data = b""
        for i in range(16):
            v = int(gdb.parse_and_eval(f"*(unsigned long*)(0x{ptr+i*8:x})")) & 0xFFFFFFFFFFFFFFFF
            data += v.to_bytes(8, "little")
        nul = data.find(b'\x00')
        s = data[:nul].decode("ascii", errors="replace") if nul >= 0 else data[:128].hex()
        gdb.write(f"\n[cmdline] saved_command_line(0x{ptr:x}) = \"{s}\"\n")
except Exception as e:
    gdb.write(f"\n[cmdline] Cannot read: {e}\n")

gdb.write("\n[DONE]\n")
end

quit
