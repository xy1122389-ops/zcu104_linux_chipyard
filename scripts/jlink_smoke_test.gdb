# jlink_smoke_test.gdb — Minimal J-Link→Rocket diagnostic
#
# What this does:
#   1. Connect to J-Link GDB server (tries multiple ports)
#   2. Halt the core
#   3. Read PC, mstatus, mcause
#   4. Test DDR read/write via SBA
#   5. Toggle LED via GPIO (0x64002000)
#   6. Report results
#
# Usage:
#   riscv64-unknown-elf-gdb -batch -x scripts/jlink_smoke_test.gdb
#
# Env vars:
#   JLINK_HOST  — J-Link host (default: 172.19.128.1)
#   JLINK_PORT  — J-Link port (default: 2331, also tries 12331)

set pagination off
set confirm off
set remotetimeout 30

python
import os, gdb, time, sys

host = os.environ.get("JLINK_HOST", "172.19.128.1")
ports = os.environ.get("JLINK_PORT", "2331,12331").split(",")
results = []

def report(tag, status, detail=""):
    r = f"[{status}] {tag}"
    if detail:
        r += f": {detail}"
    results.append(r)
    gdb.write(r + "\n")

# ============================================================
# Step 1: Connect to J-Link
# ============================================================
gdb.write("\n=== Step 1: Connect to J-Link ===\n")
connected = False
for port in ports:
    port = port.strip()
    gdb.write(f"  Trying {host}:{port} ...\n")
    for attempt in range(1, 4):
        try:
            gdb.execute(f"target remote {host}:{port}")
            gdb.write(f"  Connected on attempt {attempt} (port {port})\n")
            report("JLINK_CONNECT", "PASS", f"port={port}")
            connected = True
            break
        except gdb.error as err:
            gdb.write(f"  Attempt {attempt} failed: {err}\n")
            if attempt < 3:
                time.sleep(2)
    if connected:
        break

if not connected:
    report("JLINK_CONNECT", "FAIL", f"all ports tried: {ports}")
    gdb.write("\n========== SMOKE TEST RESULTS ==========\n")
    for r in results:
        gdb.write(r + "\n")
    gdb.write("==========================================\n")
    gdb.write("RESULT: FAIL — cannot connect to J-Link\n")
    gdb.write("Check: is JLinkGDBServerCL running on Windows?\n")
    gdb.write("  cmd: start_jlink_gdb_server.bat\n")
    raise SystemExit(1)

# ============================================================
# Step 2: Halt the core
# ============================================================
gdb.write("\n=== Step 2: Halt core ===\n")
try:
    gdb.execute("monitor halt")
    report("CORE_HALT", "PASS")
except gdb.error as err:
    report("CORE_HALT", "FAIL", str(err))
    gdb.write("\nCannot halt core — aborting remaining tests.\n")
    gdb.write("\n========== SMOKE TEST RESULTS ==========\n")
    for r in results:
        gdb.write(r + "\n")
    gdb.write("==========================================\n")
    raise SystemExit(1)

# ============================================================
# Step 3: Read CSRs
# ============================================================
gdb.write("\n=== Step 3: Read core state ===\n")
try:
    pc_out = gdb.execute("info reg pc", to_string=True).strip()
    gdb.write(f"  {pc_out}\n")
    report("READ_PC", "PASS", pc_out.split()[-1] if pc_out else "?")
except gdb.error as err:
    report("READ_PC", "FAIL", str(err))

for csr_name, csr_num in [("mstatus", "0x300"), ("mcause", "0x342"), ("mepc", "0x341")]:
    try:
        gdb.execute(f"monitor ReadCSR {csr_num}")
        report(f"READ_{csr_name.upper()}", "PASS")
    except gdb.error as err:
        report(f"READ_{csr_name.upper()}", "FAIL", str(err))

# ============================================================
# Step 4: DDR read/write test via SBA
# ============================================================
gdb.write("\n=== Step 4: DDR read/write via SBA ===\n")
test_addr = 0x80100000
test_pattern = 0xCAFEBABE
try:
    # Write
    gdb.execute(f"set *(unsigned int*){test_addr} = {test_pattern}")
    # Read back
    rb = gdb.parse_and_eval(f"*(unsigned int*){test_addr}")
    rb_val = int(rb) & 0xFFFFFFFF
    if rb_val == test_pattern:
        report("DDR_RW_SBA", "PASS", f"wrote/read 0x{test_pattern:08X}")
    else:
        report("DDR_RW_SBA", "FAIL", f"wrote 0x{test_pattern:08X}, read 0x{rb_val:08X}")
    # Clean up
    gdb.execute(f"set *(unsigned int*){test_addr} = 0")
except gdb.error as err:
    report("DDR_RW_SBA", "FAIL", str(err))

# ============================================================
# Step 5: Toggle LED via GPIO
# ============================================================
gdb.write("\n=== Step 5: Toggle LED (GPIO 0x64002000) ===\n")
GPIO_BASE = 0x64002000
GPIO_OUTPUT_EN  = GPIO_BASE + 0x08
GPIO_OUTPUT_VAL = GPIO_BASE + 0x0C
try:
    # Enable output on pin 0
    gdb.execute(f"set *(unsigned int*){GPIO_OUTPUT_EN} = 0x1")
    time.sleep(0.1)
    # Turn LED ON
    gdb.execute(f"set *(unsigned int*){GPIO_OUTPUT_VAL} = 0x1")
    time.sleep(0.5)
    # Verify
    val = gdb.parse_and_eval(f"*(unsigned int*){GPIO_OUTPUT_VAL}")
    val_int = int(val) & 0xFFFFFFFF
    if val_int & 1:
        report("LED_ON", "PASS", "DS39 should be ON now")
    else:
        report("LED_ON", "WARN", f"output_val readback = 0x{val_int:X}")

    # Blink 3 times to make it visible
    gdb.write("  Blinking LED 3 times...\n")
    for i in range(3):
        gdb.execute(f"set *(unsigned int*){GPIO_OUTPUT_VAL} = 0x0")
        time.sleep(0.3)
        gdb.execute(f"set *(unsigned int*){GPIO_OUTPUT_VAL} = 0x1")
        time.sleep(0.3)
    report("LED_BLINK", "PASS", "3 blinks completed")

    # Leave LED ON as visual indicator
    gdb.execute(f"set *(unsigned int*){GPIO_OUTPUT_VAL} = 0x1")
    gdb.write("  LED left ON as visual indicator.\n")
except gdb.error as err:
    report("LED_TOGGLE", "FAIL", str(err))

# ============================================================
# Step 6: Test SDHCI register read (0x60170000)
# ============================================================
gdb.write("\n=== Step 6: SDHCI register probe (0x60170000) ===\n")
SDHCI_BASE = 0x60170000
try:
    # Read SDHCI version register (offset 0xFC)
    ver = gdb.parse_and_eval(f"*(unsigned int*)({SDHCI_BASE} + 0xFC)")
    ver_val = int(ver) & 0xFFFFFFFF
    gdb.write(f"  SDHCI Version (0x601700FC) = 0x{ver_val:08X}\n")
    # Arasan SDHCI: vendor version in upper 8 bits, spec version in lower 8
    spec_ver = ver_val & 0xFF
    vendor_ver = (ver_val >> 8) & 0xFF
    gdb.write(f"  Spec version = 0x{spec_ver:02X}, Vendor version = 0x{vendor_ver:02X}\n")
    if ver_val != 0 and ver_val != 0xFFFFFFFF:
        report("SDHCI_READ", "PASS", f"version=0x{ver_val:08X}")
    else:
        report("SDHCI_READ", "WARN", f"version=0x{ver_val:08X} (looks like no device)")
except gdb.error as err:
    report("SDHCI_READ", "FAIL", str(err))

# ============================================================
# Summary
# ============================================================
gdb.write("\n========== SMOKE TEST RESULTS ==========\n")
pass_count = sum(1 for r in results if "[PASS]" in r)
fail_count = sum(1 for r in results if "[FAIL]" in r)
warn_count = sum(1 for r in results if "[WARN]" in r)
for r in results:
    gdb.write(r + "\n")
gdb.write(f"------------------------------------------\n")
gdb.write(f"PASS={pass_count}  FAIL={fail_count}  WARN={warn_count}\n")
if fail_count == 0:
    gdb.write("RESULT: ALL PASS\n")
else:
    gdb.write("RESULT: SOME FAILURES — see above\n")
gdb.write("==========================================\n")

# Detach cleanly
try:
    gdb.execute("detach")
except:
    pass
end
