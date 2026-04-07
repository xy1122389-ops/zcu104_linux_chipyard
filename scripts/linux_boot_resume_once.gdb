set pagination off
set confirm off
set remotetimeout 600

python
import gdb, re, time
_host = "172.19.128.1"
_port = 12331
LOG_PA = 0x80ed4060
LOG_LEN = 0x20000

gdb.write(f"[info] Connecting to {_host}:{_port}\n")
gdb.execute(f"target remote {_host}:{_port}")

pc = int(gdb.parse_and_eval("$pc"))
gdb.write(f"[state] Initial PC = 0x{pc:x}\n")

# Move past the first two Linux entry instructions; native continue from 0x80200000 is unreliable.
if pc == 0x80200000:
    gdb.execute("stepi")
    gdb.execute("stepi")
elif pc == 0x80200002:
    gdb.execute("stepi")

pc = int(gdb.parse_and_eval("$pc"))
gdb.write(f"[state] Resume PC = 0x{pc:x}\n")

RET0 = 0x80824501
for pa, val, desc in [
    (0x80601168, 0x00000013, "parse_args nop"),
    (0x806162d0, RET0, "legacy_pty_init ret0"),
    (0x80616440, RET0, "unix98_pty_init ret0"),
    (0x805b891e, RET0, "__warn ret0"),
]:
    gdb.execute(f"set *(unsigned int*){pa} = {val}")
    gdb.write(f"[patch] {desc} @ 0x{pa:x}\n")

gdb.execute("set *(unsigned short*)0x806026be = 0x0001")
gdb.write("[patch] populate_rootfs wait branch -> nop @ 0x806026be\n")

gdb.execute("set *(unsigned char*)0x806009fc = 0")
gdb.write("[patch] initramfs_async = 0 @ 0x806009fc\n")

strlen_pa = 0x805b7ea0
strlen_words = [0x43e55593, 0xc1990585, 0x80824501, 0x460385aa,
                0xc2190005, 0xbfe50505, 0x80828d0d]
for i, word in enumerate(strlen_words):
    gdb.execute(f"set *(unsigned int*)({strlen_pa + i*4}) = {word}")
gdb.write("[patch] strlen replacement installed\n")

# Clear triggers and clear dcsr ebreak+step bits.
for trig_idx in range(2):
    gdb.execute(f"monitor WriteCSR 0x7a0 {trig_idx}")
    gdb.execute("monitor WriteCSR 0x7a1 0")
    gdb.execute("monitor WriteCSR 0x7a2 0")
read_out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8})', read_out)
old_dcsr = int(m.group(1), 16)
new_dcsr = old_dcsr & ~((1 << 15) | (1 << 13) | (1 << 12) | (1 << 2))
gdb.execute(f"monitor WriteCSR 0x7b0 0x{new_dcsr:08X}")
gdb.write(f"[dcsr] 0x{old_dcsr:08X} -> 0x{new_dcsr:08X}\n")

gdb.write("[boot] continuing; external timeout will stop GDB...\n")
gdb.execute("continue")
end
