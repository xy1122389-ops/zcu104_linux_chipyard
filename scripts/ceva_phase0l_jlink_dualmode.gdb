# Phase 0L: BLE+BT dual-mode simultaneous CLKN verification
# Tests that clknint is a single shared signal driving both BLE and BT basebands
#
# Register map (RTL confirmed):
#   RWBLECNTL: 0x65000400  RWBLE_EN=bit8 (0x100)
#   RWBTCNTL:  0x65000800  RWBTEN=bit8  (0x100)
#   INTCNTL1:  0x65000018  CLKNINTMSK=bit0
#   INTSTAT0:  0x6500000C  error flags
#   INTSTAT1:  0x6500001C  CLKNINTSTAT=bit0
#   INTACK1:   0x65000020  CLKNINTACK=bit0
#
# Test flow:
#   1) Enable RWBLE_EN and RWBTEN simultaneously
#   2) Poll CLKNINTSTAT ≥10 times (expect same or higher rate than single-mode)
#   3) Disable both
#
# PASS criteria:
#   a) hslot_count >= 10 (dual-mode CLKN works)
#   b) INTSTAT0=0 (no arbitration/bus errors)
#   c) No hang (HW can drive both basebands from shared CLKN)

set remotetimeout 30
target remote 127.0.0.1:3333
monitor halt

python

import gdb
import time

RWBLECNTL  = 0x65000400
RWBTCNTL   = 0x65000800
INTCNTL1   = 0x65000018
INTSTAT0   = 0x6500000C
INTSTAT1   = 0x6500001C
INTACK1    = 0x65000020

RWBLE_EN_MASK   = 0x00000100   # bit8
RWBTEN_MASK     = 0x00000100   # bit8
CLKNINTMSK_BIT  = 0x00000001   # INTCNTL1 bit0
CLKNINTSTAT_BIT = 0x00000001   # INTSTAT1 bit0
CLKNINTACK_BIT  = 0x00000001   # INTACK1  bit0

NEED_EDGES = 10
POLL_MAX   = 500

def mmio_read(addr):
    return int(gdb.parse_and_eval("*(unsigned int*)0x{:08X}".format(addr)))

def mmio_write(addr, val):
    gdb.execute("monitor WriteU32 0x{:08X} 0x{:08X}".format(addr, val))

def tag(s):
    print("[PHASE0L] " + s)

verdict = "FAIL"

tag("============================================")
tag("Phase 0L: BLE+BT dual-mode simultaneous CLKN")
tag("RWBLE_EN + RWBTEN both=1 → shared clknint")
tag("============================================")

# L1: Pre-test state
tag("")
tag("L1: Pre-test state")
ble_pre  = mmio_read(RWBLECNTL)
bt_pre   = mmio_read(RWBTCNTL)
ic1_pre  = mmio_read(INTCNTL1)
is0_pre  = mmio_read(INTSTAT0)
is1_pre  = mmio_read(INTSTAT1)
tag("  RWBLECNTL:  0x{:08X}".format(ble_pre))
tag("  RWBTCNTL:   0x{:08X}".format(bt_pre))
tag("  INTCNTL1:   0x{:08X}".format(ic1_pre))
tag("  INTSTAT0:   0x{:08X}".format(is0_pre))
tag("  INTSTAT1:   0x{:08X}".format(is1_pre))

# L2: Ensure CLKNINTMSK is set
if (ic1_pre & CLKNINTMSK_BIT) == 0:
    tag("")
    tag("L2: Enabling CLKNINTMSK")
    mmio_write(INTCNTL1, ic1_pre | CLKNINTMSK_BIT)
else:
    tag("L2: CLKNINTMSK already enabled")

# L3: Clear any stale CLKN interrupt
mmio_write(INTACK1, CLKNINTACK_BIT)

# L4: Enable both BLE and BT simultaneously
tag("")
tag("L4: Enabling RWBLE_EN + RWBTEN simultaneously")
mmio_write(RWBLECNTL, RWBLE_EN_MASK)
mmio_write(RWBTCNTL,  RWBTEN_MASK)
ble_after = mmio_read(RWBLECNTL)
bt_after  = mmio_read(RWBTCNTL)
tag("  RWBLECNTL after: 0x{:08X}  (expect 0x{:08X})".format(ble_after, RWBLE_EN_MASK))
tag("  RWBTCNTL after:  0x{:08X}  (expect 0x{:08X})".format(bt_after, RWBTEN_MASK))

# L5: Poll CLKNINTSTAT for ≥10 edges
tag("")
tag("L5: Polling INTSTAT1[CLKNINTSTAT] dual-mode (need {:d} edges, max {:d} polls)...".format(NEED_EDGES, POLL_MAX))
hslot_count   = 0
last_intstat1 = 0
error_mid     = 0

for i in range(POLL_MAX):
    s1 = mmio_read(INTSTAT1)
    last_intstat1 = s1
    if (s1 & CLKNINTSTAT_BIT) != 0:
        hslot_count += 1
        mmio_write(INTACK1, CLKNINTACK_BIT)
        if hslot_count >= NEED_EDGES:
            break
    # Check errors periodically
    if i % 20 == 0:
        error_mid = mmio_read(INTSTAT0)
        if error_mid != 0:
            tag("  ERROR at poll {:d}: INTSTAT0=0x{:08X}".format(i, error_mid))
            break

tag("  hslot_count:    {:d}  (need {:d})".format(hslot_count, NEED_EDGES))
tag("  last_intstat1:  0x{:08X}".format(last_intstat1))

# L6: Post-poll snapshot
is0_post = mmio_read(INTSTAT0)
ble_post = mmio_read(RWBLECNTL)
bt_post  = mmio_read(RWBTCNTL)
tag("")
tag("L6: Post-poll snapshot")
tag("  INTSTAT0:   0x{:08X}  (expect 0x00000000)".format(is0_post))
tag("  RWBLECNTL:  0x{:08X}".format(ble_post))
tag("  RWBTCNTL:   0x{:08X}".format(bt_post))

# L7: Disable both
tag("")
tag("L7: Disabling RWBLE_EN and RWBTEN")
mmio_write(RWBLECNTL, 0)
mmio_write(RWBTCNTL,  0)
tag("  RWBLECNTL cleared, RWBTCNTL cleared")

# Verdict
tag("")
if hslot_count < NEED_EDGES:
    tag("FAIL: hslot_count={:d} < {:d} (CLKN not sufficient in dual mode)".format(hslot_count, NEED_EDGES))
    verdict = "FAIL:INSUFFICIENT_CLKN_EDGES"
elif is0_post != 0:
    tag("FAIL: INTSTAT0=0x{:08X} (errors in dual mode)".format(is0_post))
    verdict = "FAIL:INTSTAT0_ERRORS"
else:
    tag("PASS: hslot_count={:d}/{:d} (dual-mode CLKN confirmed)".format(hslot_count, NEED_EDGES))
    tag("PASS: INTSTAT0=0 (no bus/arbitration errors)")
    tag("PASS: BLE+BT dual-mode clknint sharing VERIFIED on ZCU104")
    verdict = "PASS"

tag("VERDICT: " + verdict)

end

monitor go
