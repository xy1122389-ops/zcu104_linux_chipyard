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
gdb.execute("add-symbol-file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf 0x80400000")
end

monitor halt

define bopensbi
  delete breakpoints
  hbreak *0x80400000
  continue
end

define bopensbi_init
  delete breakpoints
  hbreak *0x804006a4
  continue
end

define bopensbi_next
  delete breakpoints
  hbreak *0x80400660
  continue
end

define pcur
  info reg pc
  x/10i $pc
end

echo OpenSBI chain observe script loaded.\n
echo Commands:\n
echo   bopensbi      - break at OpenSBI _start (0x80400000)\n
echo   bopensbi_init - break at OpenSBI sbi_init (0x804006a4)\n
echo   bopensbi_next - break at OpenSBI fw_next_addr (0x80400660)\n
echo   pcur          - show current pc and 10 instructions\n
