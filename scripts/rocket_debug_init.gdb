set pagination off
set confirm off

python
import subprocess
import gdb

host = subprocess.check_output(
    ["bash", "-lc", "ip route | awk '/default/ {print $3; exit}'"],
    text=True,
).strip()
if not host:
    host = "172.19.128.1"
gdb.write(f"[info] Connecting to J-Link GDB Server at {host}:2331\n")
gdb.execute(f"target remote {host}:2331")
end

monitor halt

define bmain
  delete breakpoints
  hbreak *0x10144
  set $pc = 0x10000
  continue
end

define bloop
  delete breakpoints
  hbreak *0x10398
  continue
end

define bled
  delete breakpoints
  hbreak *0x10464
  continue
end

define bddr
  delete breakpoints
  hbreak *0x101bc
  set $pc = 0x10000
  continue
end

define pcur
  info reg pc
  x/10i $pc
end

echo Rocket debug init loaded.\n
echo Commands:\n
echo   bmain  - break at main (0x10144)\n
echo   bloop  - break at count loop hot spot (0x10398)\n
echo   bled   - break at LED toggle (0x10464)\n
echo   bddr   - break at DDR fixed first write (0x101bc)\n
echo   pcur   - show current pc and 10 instructions\n
