echo [preclean] Clearing stale debug trigger state before Phase 1\n
monitor WriteCSR 0x7a0 0
monitor WriteCSR 0x7a1 0
monitor WriteCSR 0x7a2 0
monitor WriteCSR 0x7a0 1
monitor WriteCSR 0x7a1 0
monitor WriteCSR 0x7a2 0

python
import gdb, re

read_out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
match = re.search(r'(?:0x)?([0-9A-Fa-f]{8})', read_out)
if match:
    old_dcsr = int(match.group(1), 16)
    new_dcsr = old_dcsr & ~((1 << 15) | (1 << 13) | (1 << 12) | (1 << 2))
    gdb.write(f"[preclean] dcsr old=0x{old_dcsr:08X} new=0x{new_dcsr:08X}\\n")
    gdb.execute(f"monitor WriteCSR 0x7b0 0x{new_dcsr:08X}")
else:
    gdb.write(f"[preclean] could not parse dcsr: {read_out.strip()}\\n")
end
info reg pc