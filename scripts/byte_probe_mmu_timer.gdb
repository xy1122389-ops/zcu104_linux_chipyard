# byte_probe_mmu_timer.gdb — Timer IRQ variant
set pagination off
set confirm off

python
import gdb, os, time, struct, re

host = "172.19.128.1"
port = os.environ.get("JLINK_PORT", "12331")

for attempt in range(4):
    try:
        gdb.execute(f"target remote {host}:{port}")
        gdb.write(f"[ok] Connected on attempt {attempt+1}\n")
        break
    except gdb.error as e:
        gdb.write(f"[warn] Attempt {attempt+1} failed: {e}\n")
        if attempt == 3:
            raise

time.sleep(0.5)

dcsr_out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]+)', dcsr_out)
if m:
    dcsr = int(m.group(1), 16)
    dcsr_new = (dcsr & ~3) | 3
    gdb.execute(f"monitor WriteCSR 0x7b0 0x{dcsr_new:x}")
    gdb.write(f"[ok] dcsr: 0x{dcsr:x} -> 0x{dcsr_new:x} (M-mode)\n")

bin_path = os.path.join(os.environ.get("PWD", "/root/chipyard/fpga"), "tests/byte_probe_mmu_timer.bin")
gdb.write(f"[load] {bin_path}\n")
gdb.execute(f"restore {bin_path} binary 0x81200000")
gdb.write("[ok] Binary loaded at 0x81200000\n")

gdb.execute("set $pc = 0x81200000")
gdb.execute("monitor go")
gdb.write("[run] CPU running with timer IRQs ...\n")

# Timer IRQ test: 10K iters with IRQs every 500 cycles.
# At 50 MHz, 500 cycles = 10 us.  Each iter ~20 cycles + IRQ overhead.
# Estimate ~2-5 seconds. Wait 15s.
time.sleep(15)

gdb.execute("monitor halt")
time.sleep(1)
try:
    gdb.execute("maintenance flush register-cache")
except:
    pass

pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"[halt] PC = 0x{pc:016x}\n")

# Read results (extended to 0x80 for timer_count at +0x78)
res_file = "/tmp/byte_probe_timer_result.bin"
gdb.execute(f"dump binary memory {res_file} 0x81224000 0x81224080")

with open(res_file, "rb") as f:
    data = f.read()

def u64(off):
    return struct.unpack_from("<Q", data, off)[0]

magic       = u64(0x00)
sb_mm       = u64(0x08)
total       = u64(0x10)
sb_1st_iter = u64(0x18)
sb_1st_exp  = u64(0x20)
sb_1st_act  = u64(0x28)
sb_1st_addr = u64(0x30)
lbu_mm      = u64(0x38)
lbu_1st_iter= u64(0x40)
lbu_1st_exp = u64(0x48)
lbu_1st_act = u64(0x50)
passfail    = u64(0x58)
trap_cause  = u64(0x60)
trap_val    = u64(0x68)
trap_epc    = u64(0x70)
timer_count = u64(0x78)

magic_str = {0x444F4E45: "DONE", 0x54524150: "TRAP"}.get(magic & 0xFFFFFFFF, f"UNKNOWN(0x{magic:x})")
pf_str    = {0x50415353: "PASS", 0x4641494C: "FAIL"}.get(passfail & 0xFFFFFFFF, f"?(0x{passfail:x})")

gdb.write("\n" + "="*60 + "\n")
gdb.write("  BYTE PROBE MMU + TIMER — RESULTS\n")
gdb.write("="*60 + "\n")
gdb.write(f"  Status:           {magic_str}\n")
gdb.write(f"  Total iterations: {total}\n")
gdb.write(f"  Timer IRQs taken: {timer_count}\n")
gdb.write(f"  sb  mismatches:   {sb_mm}\n")
gdb.write(f"  lbu mismatches:   {lbu_mm}\n")
gdb.write(f"  Verdict:          {pf_str}\n")

if sb_mm > 0:
    gdb.write(f"\n  --- sb first failure ---\n")
    gdb.write(f"  iteration: {sb_1st_iter}\n")
    gdb.write(f"  addr:      0x{sb_1st_addr:016x}\n")
    gdb.write(f"  expected:  0x{sb_1st_exp:016x}\n")
    gdb.write(f"  actual:    0x{sb_1st_act:016x}\n")
    diff = sb_1st_exp ^ sb_1st_act
    for b in range(8):
        eb = (sb_1st_exp >> (b*8)) & 0xFF
        ab = (sb_1st_act >> (b*8)) & 0xFF
        if eb != ab:
            gdb.write(f"    byte[{b}]: exp=0x{eb:02x} act=0x{ab:02x}\n")

if lbu_mm > 0:
    gdb.write(f"\n  --- lbu first failure ---\n")
    gdb.write(f"  iteration:     {lbu_1st_iter}\n")
    gdb.write(f"  expected byte: 0x{lbu_1st_exp:02x}\n")
    gdb.write(f"  actual byte:   0x{lbu_1st_act:02x}\n")

if magic_str == "TRAP":
    gdb.write(f"\n  --- S-mode trap ---\n")
    gdb.write(f"  scause: 0x{trap_cause:016x}\n")
    gdb.write(f"  stval:  0x{trap_val:016x}\n")
    gdb.write(f"  sepc:   0x{trap_epc:016x}\n")

if magic_str == "UNKNOWN(0x0)":
    gdb.write("\n  *** Results area all zeros — test may not have finished ***\n")
    gdb.write(f"  Current PC: 0x{pc:016x}\n")
    for off in [0, 8, 16]:
        gdb.write(f"  result[0x{off:02x}] = 0x{u64(off):016x}\n")

gdb.write("="*60 + "\n")

summary = "/tmp/byte_probe_mmu_timer_result.txt"
with open(summary, "w") as f:
    f.write(f"magic={magic_str}\n")
    f.write(f"sb_mismatch={sb_mm}\n")
    f.write(f"lbu_mismatch={lbu_mm}\n")
    f.write(f"total={total}\n")
    f.write(f"timer_irqs={timer_count}\n")
    f.write(f"verdict={pf_str}\n")
    if sb_mm > 0:
        f.write(f"sb_1st_iter={sb_1st_iter}\n")
        f.write(f"sb_1st_addr=0x{sb_1st_addr:016x}\n")
        f.write(f"sb_1st_exp=0x{sb_1st_exp:016x}\n")
        f.write(f"sb_1st_act=0x{sb_1st_act:016x}\n")
    if lbu_mm > 0:
        f.write(f"lbu_1st_iter={lbu_1st_iter}\n")
        f.write(f"lbu_1st_exp=0x{lbu_1st_exp:02x}\n")
        f.write(f"lbu_1st_act=0x{lbu_1st_act:02x}\n")
    if magic_str == "TRAP":
        f.write(f"trap_cause=0x{trap_cause:016x}\n")
        f.write(f"trap_val=0x{trap_val:016x}\n")
        f.write(f"trap_epc=0x{trap_epc:016x}\n")

gdb.write(f"\n[saved] {summary}\n")
end

quit
