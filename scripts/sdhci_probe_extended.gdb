# Extended SDHCI probe - test multiple addresses systematically
set confirm off
set pagination off
set architecture riscv:rv64

python
import os, gdb, time

_host = os.environ.get("JLINK_HOST", "172.19.128.1")
_port = int(os.environ.get("JLINK_PORT", "12331"))
gdb.execute(f"target remote {_host}:{_port}")
gdb.execute("monitor halt")
time.sleep(1)

gdb.write("\n=== Extended SDHCI Probe ===\n\n")
gdb.execute("monitor WriteCSR 0x180 0")

# Probe every 4 bytes from 0x60170000 to 0x60170100
base = 0x60170000
results = []

for offset in range(0, 0x104, 4):
    addr = base + offset
    try:
        val = int(gdb.parse_and_eval(f"*(unsigned int*)0x{addr:x}"))
        results.append((offset, val, True))
    except Exception:
        results.append((offset, 0, False))

# Print results  
ok_count = sum(1 for _, _, ok in results if ok)
fail_count = sum(1 for _, _, ok in results if not ok)

gdb.write(f"  Results: {ok_count} OK, {fail_count} FAIL out of {len(results)} addresses\n\n")

for offset, val, ok in results:
    status = f"0x{val:08X}" if ok else "ERROR"
    # Mark known registers
    names = {
        0x00: "SDMA_ADDR", 0x04: "BLK_SIZE/CNT", 0x08: "ARG1",
        0x0C: "XFER_MODE/CMD", 0x10: "RESP0", 0x14: "RESP1",
        0x18: "RESP2", 0x1C: "RESP3", 0x20: "BUF_DATA",
        0x24: "PRESENT_STATE", 0x28: "HOST_CTRL1/PWR", 0x2C: "CLK_CTRL",
        0x30: "TIMEOUT_CTRL/SW_RST", 0x34: "INT_STATUS", 0x38: "INT_ENABLE",
        0x3C: "INT_SIGNAL", 0x40: "CAPS_LO", 0x44: "CAPS_HI",
        0x48: "MAX_CURR", 0x4C: "MAX_CURR_HI",
        0xFC: "VERSION",
    }
    name = names.get(offset, "")
    gdb.write(f"  0x{base+offset:08X} [+0x{offset:02X}] {name:20s} = {status}\n")

gdb.write("\n=== Probe complete ===\n")
end

quit
