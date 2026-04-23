set confirm off
set pagination off
set architecture riscv:rv64
set remotetimeout 30

python
import gdb

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

safe_exec("x/1wx 0x601700FC", "read VERSION first time")
safe_exec("info reg pc", "pc after VERSION #1")
safe_exec("monitor ReadCSR 0x342", "mcause after VERSION #1")
safe_exec("monitor ReadCSR 0x305", "mtvec after VERSION #1")
safe_exec("monitor ReadCSR 0x341", "mepc after VERSION #1")

safe_exec("x/1wx 0x601700FC", "read VERSION second time")
safe_exec("info reg pc", "pc after VERSION #2")
safe_exec("monitor ReadCSR 0x342", "mcause after VERSION #2")
safe_exec("monitor ReadCSR 0x305", "mtvec after VERSION #2")
safe_exec("monitor ReadCSR 0x341", "mepc after VERSION #2")

safe_exec("x/1wx 0x60170040", "read CAPS_LO")
safe_exec("info reg pc", "pc after CAPS_LO")
safe_exec("monitor ReadCSR 0x342", "mcause after CAPS_LO")
safe_exec("monitor ReadCSR 0x305", "mtvec after CAPS_LO")
safe_exec("monitor ReadCSR 0x341", "mepc after CAPS_LO")

# Probe whether non-SDIO reads are still alive in the same GDB session
# after the 0x60170040 access fails.
safe_exec("x/4wx 0x10000", "BootROM after CAPS_LO")
safe_exec("x/2wx 0x200bff8", "CLINT mtime after CAPS_LO")
safe_exec("monitor halt", "rehalt after CAPS_LO")
safe_exec("disconnect", "disconnect")
gdb.execute("quit")
end
