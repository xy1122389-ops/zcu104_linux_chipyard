# Phase 1A: CPU EM MMIO Window Verification
#
# Verifies that the new CPU AHB EM access port works correctly:
# - CPU can read/write EM BRAM at 0x65010000-0x6501FFFF
# - EM data persists (write then read back)
# - CEVA BT core still functions (CLKN active) after RTL change
#
# EM window: 0x65010000 - 0x6501FFFF (64KB = 16384 x 32-bit words)
# Word 0 = 0x65010000, Word N = 0x65010000 + N*4
#
# Test sequence:
#   A1: Sanity read EM[0..3] before write (should be 0x0 or previous content)
#   A2: Write known patterns to EM[0..15] (word0..word15)
#   A3: Readback EM[0..15] and verify exact match
#   A4: Write 0x12345678 to EM[256] (offset 0x400) and EM[4095] (end area)
#   A5: Readback EM[256] and EM[4095] - verify
#   A6: Write 0xDEADBEEF to EM[8192] (upper half) and readback
#   A7: BT init + CLKN check (verify CEVA core still functional)
#   A8: Read EM[0..3] AFTER CEVA is running (verify CEVA hasn't trashed our writes)
#   A9: Cleanup and final status
#
# PASS criteria:
#   a) EM[0..15] write+readback exact match
#   b) EM[256] and EM[4095] write+readback match
#   c) EM[8192] (upper half) write+readback match
#   d) CLKN active (5/5 edges) after RTL change
#   e) No DM_INTSTAT0 errors

set remotetimeout 30
target remote 127.0.0.1:3333
monitor halt

python

import gdb, time

EM_BASE  = 0x65010000   # CPU EM MMIO window
EM_WORDS = 16384        # 64KB / 4
DEBUGADDMAX_ADDR = 0x65000058
DEBUGADDMIN_ADDR = 0x6500005C

# CEVA DM/BT for CLKN check
DM_RWDMCNTL   = 0x65000000
DM_INTSTAT0   = 0x6500000C
DM_INTCNTL1   = 0x65000018
DM_INTSTAT1   = 0x6500001C
DM_INTACK1    = 0x65000020
DM_TIMGENCNTL = 0x650000E0
BT_RWBTCNTL   = 0x65000800
BT_INTCNTL0   = 0x6500080C
BT_INTACK0    = 0x65000814
BT_CURRENTRXDESC = 0x65000828
RWBTEN_MASK    = 0x00000100
BT_RWBTCNTL_INIT = 0x00000E0D
BT_INTCNTL0_INIT = 0x00010016
TIMGENCNTL_VAL   = 0x011800C8
DM_MASTER_SOFT_RST = 0x80000000

def mmio_read(addr):
    # Use GDB native memory read (RSP 'm' packet → J-Link SBA)
    # This works on J-Link v7.82b where monitor mem32/ReadU32 are not supported
    val = gdb.parse_and_eval("*(unsigned int*)0x{:08X}".format(addr))
    return int(val) & 0xFFFFFFFF

def mmio_write(addr, val):
    # MMIO writes via native GDB download path can wedge the CEVA window.
    # Reuse the established J-Link monitor WriteU32 path used by other CEVA scripts.
    gdb.execute("monitor WriteU32 0x{:08X} 0x{:08X}".format(addr, val))

def em_read(word_idx):
    return mmio_read(EM_BASE + word_idx * 4)

def em_write(word_idx, val):
    mmio_write(EM_BASE + word_idx * 4, val)

def tag(s):
    print("[PHASE1A] " + s)

verdict = "FAIL"
fails = []

tag("=================================================")
tag("Phase 1A: CPU EM MMIO Window Verification")
tag("  EM window: 0x{:08X} - 0x{:08X}".format(EM_BASE, EM_BASE + EM_WORDS*4 - 1))
tag("=================================================")

# Match the previously verified EM access flow: open the full local debug range
# before touching the 0x6501_xxxx window.
tag("")
tag("A0: Open CEVA EM debug range")
mmio_write(DEBUGADDMAX_ADDR, 0xFFFFFFFF)
mmio_write(DEBUGADDMIN_ADDR, 0x00000000)
debug_add_max = mmio_read(DEBUGADDMAX_ADDR)
debug_add_min = mmio_read(DEBUGADDMIN_ADDR)
tag("  DEBUGADDMAX = 0x{:08X}".format(debug_add_max))
tag("  DEBUGADDMIN = 0x{:08X}".format(debug_add_min))
if debug_add_max != 0xFFFFFFFF or debug_add_min != 0x00000000:
    fails.append("DEBUG_ADDR_WINDOW")

# A1: Read EM[0..3] before write
tag("")
tag("A1: Pre-write EM[0..3] snapshot")
for i in range(4):
    v = em_read(i)
    tag("  EM[{}] = 0x{:08X}".format(i, v))

# A2: Write patterns to EM[0..15]
tag("")
tag("A2: Write 16 test patterns to EM[0..15]")
PATTERNS = [
    0xDEADC0DE, 0x12345678, 0xABCDEF01, 0x55AA55AA,
    0xCAFEBABE, 0xFEEDFACE, 0x0B1ECAFE, 0xDEADBEEF,
    0x01234567, 0x89ABCDEF, 0xFEDCBA98, 0x76543210,
    0xA5A5A5A5, 0x5A5A5A5A, 0xAAAAAAAA, 0x55555555,
]
for i, p in enumerate(PATTERNS):
    em_write(i, p)
tag("  Written 16 patterns OK")

# A3: Readback EM[0..15]
tag("")
tag("A3: Readback EM[0..15] - verify patterns")
match_count = 0
for i, p in enumerate(PATTERNS):
    rb = em_read(i)
    match = rb == p
    if match:
        match_count += 1
    else:
        tag("  MISMATCH EM[{}]: wrote 0x{:08X} read 0x{:08X}".format(i, p, rb))
tag("  Match: {}/{} patterns".format(match_count, len(PATTERNS)))
if match_count != len(PATTERNS):
    fails.append("EM_PATTERN_MISMATCH_0_15")
else:
    tag("  PASS: All 16 patterns matched")

# A4: Write to EM[256] and EM[4095] (boundary areas)
tag("")
tag("A4: Write to EM[256] and EM[4095] boundary areas")
em_write(256, 0x12344321)
em_write(4095, 0xFEDCCDEF)
tag("  EM[256] = 0x12344321, EM[4095] = 0xFEDCCDEF written")

# A5: Readback boundary areas
tag("")
tag("A5: Readback EM[256] and EM[4095]")
v256  = em_read(256)
v4095 = em_read(4095)
tag("  EM[256]  = 0x{:08X}  expect 0x12344321  {}".format(v256, "PASS" if v256==0x12344321 else "FAIL"))
tag("  EM[4095] = 0x{:08X}  expect 0xFEDCCDEF  {}".format(v4095, "PASS" if v4095==0xFEDCCDEF else "FAIL"))
if v256 != 0x12344321 or v4095 != 0xFEDCCDEF:
    fails.append("EM_BOUNDARY")

# A6: Write upper half EM[8192] (addr 0x65018000)
tag("")
tag("A6: Write/read EM[8192] (upper half, 0x{:08X})".format(EM_BASE + 8192*4))
em_write(8192, 0xDEADBEEF)
v8192 = em_read(8192)
tag("  EM[8192] = 0x{:08X}  expect 0xDEADBEEF  {}".format(v8192, "PASS" if v8192==0xDEADBEEF else "FAIL"))
if v8192 != 0xDEADBEEF:
    fails.append("EM_UPPER_HALF")

# A7: BT init + CLKN check
tag("")
tag("A7: CEVA BT init + CLKN check (verify IP still functional)")
mmio_write(DM_RWDMCNTL, DM_MASTER_SOFT_RST)
for i in range(50):
    if (mmio_read(DM_RWDMCNTL) & DM_MASTER_SOFT_RST) == 0:
        break
mmio_write(DM_TIMGENCNTL, TIMGENCNTL_VAL)
mmio_write(BT_INTCNTL0, BT_INTCNTL0_INIT)
mmio_write(BT_INTACK0, 0xFFFFFFFF)
mmio_write(BT_CURRENTRXDESC, 0)
mmio_write(BT_RWBTCNTL, BT_RWBTCNTL_INIT | RWBTEN_MASK)
ic1 = mmio_read(DM_INTCNTL1) | 0x01
mmio_write(DM_INTCNTL1, ic1)
mmio_write(DM_INTACK1, 0x01)
clkn = 0
for _ in range(300):
    if mmio_read(DM_INTSTAT1) & 0x01:
        clkn += 1
        mmio_write(DM_INTACK1, 0x01)
        if clkn >= 5:
            break
tag("  CLKN edges: {}/5  {}".format(clkn, "PASS" if clkn >= 5 else "FAIL"))
if clkn < 5:
    fails.append("CLKN_FAIL")

# A8: Re-read EM[0..3] after CEVA running (verify no corruption)
tag("")
tag("A8: Re-read EM[0..3] after CEVA running (check for corruption)")
for i in range(4):
    rb = em_read(i)
    expected = PATTERNS[i]
    ok = rb == expected
    tag("  EM[{}] = 0x{:08X}  expected 0x{:08X}  {}".format(i, rb, expected, "OK" if ok else "CHANGED"))
    # Note: CEVA firmware may legitimately write EM during init, don't fail on this

# A9: Final DM_INTSTAT0 check
tag("")
tag("A9: Final error check")
dm_intstat0 = mmio_read(DM_INTSTAT0)
tag("  DM_INTSTAT0: 0x{:08X}  (expect 0)".format(dm_intstat0))
if dm_intstat0 != 0:
    fails.append("DM_INTSTAT0")

# Disable RWBTEN
mmio_write(BT_RWBTCNTL, BT_RWBTCNTL_INIT)

# Verdict
tag("")
if len(fails) == 0:
    tag("PASS: EM[0..15] patterns verified (16/16)")
    tag("PASS: EM boundary areas (256, 4095) verified")
    tag("PASS: EM upper half (8192) verified")
    tag("PASS: CEVA BT core still functional (CLKN 5/5)")
    tag("PASS: DM_INTSTAT0=0")
    tag("")
    tag("PASS: CPU EM MMIO window FULLY VERIFIED — EM accessible at 0x65010000")
    verdict = "PASS"
else:
    tag("FAIL fields: " + str(fails))
    verdict = "FAIL:" + "+".join(fails)

tag("VERDICT: " + verdict)

end

monitor go
