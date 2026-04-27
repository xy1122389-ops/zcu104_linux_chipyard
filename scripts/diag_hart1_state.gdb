# Quick diagnostic: connect to J-Link, halt, inspect both harts.
# Usage: connect to a system that's already booted/running.
set pagination off
set confirm off
set print thread-events off
set remotetimeout 60

python
import gdb, os
host = os.environ.get("JLINK_HOST", "127.0.0.1")
port = os.environ.get("JLINK_PORT", "3333")
gdb.execute(f"target remote {host}:{port}")
end

monitor halt
echo \n=== info threads ===\n
info threads

echo \n=== Hart 0 (thread 1) ===\n
thread 1
info reg pc ra sp
monitor ReadCSR 0x180
monitor ReadCSR 0x7b0
monitor ReadCSR 0x141
monitor ReadCSR 0x142
monitor ReadCSR 0x300
monitor ReadCSR 0x305

echo \n=== Hart 1 (thread 2) ===\n
thread 2
info reg pc ra sp
monitor ReadCSR 0x180
monitor ReadCSR 0x7b0
monitor ReadCSR 0x141
monitor ReadCSR 0x142
monitor ReadCSR 0x300
monitor ReadCSR 0x305
echo \n=== Hart 1 disasm @PC ===\n
x/16i $pc

monitor go
detach
quit
