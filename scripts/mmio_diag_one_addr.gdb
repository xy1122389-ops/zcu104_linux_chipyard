set confirm off
set pagination off
set architecture riscv:rv64
set remotetimeout 30

python
import os
import gdb

addr = os.environ.get("MMIO_ADDR", "0x601700FC")
label = os.environ.get("MMIO_LABEL", addr)

def safe_exec(cmd, label):
    gdb.write(f"=== {label} ===\n")
    try:
        out = gdb.execute(cmd, to_string=True)
        if out:
            gdb.write(out)
        return True
    except gdb.error as exc:
        gdb.write(f"[gdb-error] {cmd}: {exc}\n")
        return False

safe_exec("target remote :3333", "connect")
safe_exec("monitor halt", "halt")
safe_exec("info reg pc", "pc before")
safe_exec("monitor ReadCSR 0x342", "mcause before")
safe_exec("monitor ReadCSR 0x305", "mtvec before")
safe_exec("monitor ReadCSR 0x341", "mepc before")

safe_exec(f"x/1wx {addr}", f"read {label}")
safe_exec("info reg pc", "pc after")
safe_exec("monitor ReadCSR 0x342", "mcause after")
safe_exec("monitor ReadCSR 0x305", "mtvec after")
safe_exec("monitor ReadCSR 0x341", "mepc after")

safe_exec("x/4wx 0x10000", "BootROM after")
safe_exec("x/2wx 0x200bff8", "CLINT mtime after")
safe_exec("monitor halt", "rehalt after")
safe_exec("disconnect", "disconnect")
gdb.execute("quit")
end
