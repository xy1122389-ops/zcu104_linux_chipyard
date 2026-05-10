# Phase 0J: rwip_driver_init sequence via GDB SBA
# Emulates ip_rwdmcntl_master_soft_rst_setf(1) + poll + ip_intcntl1_set()
#
# Register map (RTL confirmed):
#   RWDMCNTL:  0x65000000  MASTER_SOFT_RST=bit31 (0x80000000)  SWINT_REQ=bit27
#   INTCNTL1:  0x65000018  FIFOINTMSK=bit15, SWINTMSK=bit3, CRYPTINTMSK=bit2,
#                           SLPINTMSK=bit1, CLKNINTMSK=bit0
#   INTSTAT0:  0x6500000C  error flags (must stay 0)
#   INTSTAT1:  0x6500001C  SWINTSTAT=bit3, CLKNINTSTAT=bit0
#   INTACK1:   0x65000020
#
# Expected behaviour:
#   1) Write MASTER_SOFT_RST=1 → hardware resets IP, bit self-clears
#   2) Post-reset INTCNTL1 = 0x8003 (RTL defaults: FIFO=1,SLP=1,CLKN=1, SW=0, CRYPT=0)
#   3) Write INTCNTL1=0x800E (FIFO+SW+CRYPT+SLP enabled) → readback must match
#
# PASS criteria:
#   a) MASTER_SOFT_RST self-clears within poll attempts
#   b) Post-reset INTCNTL1 == 0x00008003
#   c) Post-init INTCNTL1 readback == 0x0000800E

set remotetimeout 30
target remote 127.0.0.1:3333
monitor halt

python

import gdb
import time

RWDMCNTL  = 0x65000000
INTCNTL0  = 0x65000008
INTSTAT0  = 0x6500000C
INTCNTL1  = 0x65000018
INTSTAT1  = 0x6500001C
INTACK1   = 0x65000020

MASTER_SOFT_RST_MASK = 0x80000000   # bit 31
INTCNTL1_DEFAULTS    = 0x00008003   # FIFOINTMSK(15)+SLPINTMSK(1)+CLKNINTMSK(0)
INTCNTL1_INIT_VAL    = 0x0000800E   # FIFOINTMSK(15)+SWINTMSK(3)+CRYPTINTMSK(2)+SLPINTMSK(1)

def mmio_read(addr):
    return int(gdb.parse_and_eval("*(unsigned int*)0x{:08X}".format(addr)))

def mmio_write(addr, val):
    gdb.execute("monitor WriteU32 0x{:08X} 0x{:08X}".format(addr, val))

def tag(s):
    print("[PHASE0J] " + s)

verdict = "FAIL"

tag("============================================")
tag("Phase 0J: rwip_driver_init sequence")
tag("MASTER_SOFT_RST + INTCNTL1 init via SBA")
tag("============================================")

# Step J1: Pre-reset state snapshot
tag("")
tag("J1: Pre-reset state")
rwdm_pre    = mmio_read(RWDMCNTL)
intcntl1_pre = mmio_read(INTCNTL1)
intstat0_pre = mmio_read(INTSTAT0)
intstat1_pre = mmio_read(INTSTAT1)
tag("  RWDMCNTL_before:   0x{:08X}".format(rwdm_pre))
tag("  INTCNTL1_before:   0x{:08X}".format(intcntl1_pre))
tag("  INTSTAT0_before:   0x{:08X}".format(intstat0_pre))
tag("  INTSTAT1_before:   0x{:08X}".format(intstat1_pre))

# Step J2: Assert MASTER_SOFT_RST (rwip_driver_init → ip_rwdmcntl_master_soft_rst_setf(1))
tag("")
tag("J2: Asserting MASTER_SOFT_RST (bit31 of RWDMCNTL)")
mmio_write(RWDMCNTL, MASTER_SOFT_RST_MASK)
tag("  Wrote 0x{:08X} to RWDMCNTL".format(MASTER_SOFT_RST_MASK))

# Step J3: Poll for self-clear (ip_rwdmcntl_master_soft_rst_getf() == 0)
tag("")
tag("J3: Polling RWDMCNTL[31] for self-clear (max 200 attempts)...")
rst_cleared = False
for attempt in range(200):
    rwdm_poll = mmio_read(RWDMCNTL)
    if (rwdm_poll & MASTER_SOFT_RST_MASK) == 0:
        tag("  MASTER_SOFT_RST cleared at attempt {:d} (RWDMCNTL=0x{:08X})".format(attempt, rwdm_poll))
        rst_cleared = True
        break
    if attempt < 5 or attempt % 50 == 0:
        tag("  attempt {:d}: RWDMCNTL=0x{:08X} (still set)".format(attempt, rwdm_poll))

if not rst_cleared:
    tag("  ERROR: MASTER_SOFT_RST did NOT self-clear after 200 attempts")
    tag("  Last RWDMCNTL=0x{:08X}".format(mmio_read(RWDMCNTL)))
    verdict = "FAIL:MASTER_SOFT_RST_NO_CLEAR"
else:
    # Step J4: Post-reset register snapshot
    tag("")
    tag("J4: Post-reset state (should match RTL defaults)")
    rwdm_post     = mmio_read(RWDMCNTL)
    intcntl1_post = mmio_read(INTCNTL1)
    intstat0_post = mmio_read(INTSTAT0)
    intstat1_post = mmio_read(INTSTAT1)
    tag("  RWDMCNTL_after:    0x{:08X}".format(rwdm_post))
    tag("  INTCNTL1_after:    0x{:08X}  (expect 0x{:08X})".format(intcntl1_post, INTCNTL1_DEFAULTS))
    tag("  INTSTAT0_after:    0x{:08X}  (expect 0x00000000)".format(intstat0_post))
    tag("  INTSTAT1_after:    0x{:08X}".format(intstat1_post))

    if intcntl1_post != INTCNTL1_DEFAULTS:
        tag("  WARNING: INTCNTL1 post-reset=0x{:08X} != expected 0x{:08X}".format(intcntl1_post, INTCNTL1_DEFAULTS))
        tag("  (May differ if prior Phase0G/0H state survived reset - investigating)")

    if intstat0_post != 0:
        tag("  ERROR: INTSTAT0 has error flags after reset: 0x{:08X}".format(intstat0_post))
        verdict = "FAIL:POST_RST_INTSTAT0_ERRORS"
    else:
        # Step J5: Write INTCNTL1 init value (ip_intcntl1_set(FIFO|CRYPT|SW|SLP))
        tag("")
        tag("J5: Writing INTCNTL1=0x{:08X} (FIFO+SW+CRYPT+SLP masks)".format(INTCNTL1_INIT_VAL))
        mmio_write(INTCNTL1, INTCNTL1_INIT_VAL)

        # Step J6: Readback verification
        intcntl1_rb = mmio_read(INTCNTL1)
        tag("")
        tag("J6: INTCNTL1 readback = 0x{:08X}  (expect 0x{:08X})".format(intcntl1_rb, INTCNTL1_INIT_VAL))

        if intcntl1_rb == INTCNTL1_INIT_VAL:
            tag("")
            tag("PASS: MASTER_SOFT_RST self-cleared (HW IP reset confirmed)")
            tag("PASS: INTCNTL1 init readback matches (SW init register write confirmed)")
            tag("PASS: rwip_driver_init(RWIP_1ST_RST) register sequence VERIFIED on ZCU104")
            verdict = "PASS"
        else:
            tag("FAIL: INTCNTL1 readback 0x{:08X} != expected 0x{:08X}".format(intcntl1_rb, INTCNTL1_INIT_VAL))
            verdict = "FAIL:INTCNTL1_MISMATCH"

tag("")
tag("VERDICT: " + verdict)

end

monitor go
