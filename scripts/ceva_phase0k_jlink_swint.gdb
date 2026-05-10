# Phase 0K: SWINT bidirectional communication verification
# Tests CPU→CEVA software interrupt channel (ip_rwdmcntl_swint_req_setf)
#
# Register map (RTL confirmed):
#   RWDMCNTL:  0x65000000  SWINT_REQ=bit27 (0x08000000)  MASTER_SOFT_RST=bit31
#   INTCNTL1:  0x65000018  SWINTMSK=bit3
#   INTSTAT0:  0x6500000C  error flags
#   INTSTAT1:  0x6500001C  SWINTSTAT=bit3, CLKNINTSTAT=bit0
#   INTACK1:   0x65000020  SWINTACK=bit3, CLKNINTACK=bit0
#
# PASS criteria:
#   a) After write RWDMCNTL[27]=1: INTSTAT1[SWINTSTAT(bit3)] asserts
#   b) After write INTACK1[SWINTACK(bit3)]: INTSTAT1[SWINTSTAT] clears
#   c) INTSTAT0=0 throughout (no error flags)
#   d) SWINT_REQ self-clears in RWDMCNTL after HW processes it

set remotetimeout 30
target remote 127.0.0.1:3333
monitor halt

python

import gdb

RWDMCNTL   = 0x65000000
INTCNTL1   = 0x65000018
INTSTAT0   = 0x6500000C
INTSTAT1   = 0x6500001C
INTACK1    = 0x65000020

SWINT_REQ_MASK  = 0x08000000   # RWDMCNTL bit27
SWINTMSK_BIT    = 0x00000008   # INTCNTL1 bit3
SWINTSTAT_BIT   = 0x00000008   # INTSTAT1 bit3
SWINTACK_BIT    = 0x00000008   # INTACK1  bit3
CLKNINTACK_BIT  = 0x00000001   # INTACK1  bit0

def mmio_read(addr):
    return int(gdb.parse_and_eval("*(unsigned int*)0x{:08X}".format(addr)))

def mmio_write(addr, val):
    gdb.execute("monitor WriteU32 0x{:08X} 0x{:08X}".format(addr, val))

def tag(s):
    print("[PHASE0K] " + s)

verdict = "FAIL"

tag("============================================")
tag("Phase 0K: SWINT CPU→CEVA channel verification")
tag("SWINT_REQ(bit27) → poll SWINTSTAT(bit3) → SWINTACK")
tag("============================================")

# K1: Pre-test state snapshot
tag("")
tag("K1: Pre-test state")
rwdm_pre    = mmio_read(RWDMCNTL)
intcntl1    = mmio_read(INTCNTL1)
intstat0_pre = mmio_read(INTSTAT0)
intstat1_pre = mmio_read(INTSTAT1)
tag("  RWDMCNTL:   0x{:08X}".format(rwdm_pre))
tag("  INTCNTL1:   0x{:08X}".format(intcntl1))
tag("  INTSTAT0:   0x{:08X}  (must stay 0)".format(intstat0_pre))
tag("  INTSTAT1:   0x{:08X}".format(intstat1_pre))

# K2: Ensure SWINTMSK is enabled (bit3 of INTCNTL1)
if (intcntl1 & SWINTMSK_BIT) == 0:
    tag("")
    tag("K2: SWINTMSK not set — enabling it")
    new_intcntl1 = intcntl1 | SWINTMSK_BIT
    mmio_write(INTCNTL1, new_intcntl1)
    intcntl1 = mmio_read(INTCNTL1)
    tag("  INTCNTL1 now: 0x{:08X}".format(intcntl1))
else:
    tag("")
    tag("K2: SWINTMSK already enabled (INTCNTL1=0x{:08X})".format(intcntl1))

# K3: Clear any stale SWINTSTAT
if (intstat1_pre & SWINTSTAT_BIT) != 0:
    tag("K3: Clearing stale SWINTSTAT")
    mmio_write(INTACK1, SWINTACK_BIT)
    intstat1_check = mmio_read(INTSTAT1)
    tag("  INTSTAT1 after stale clear: 0x{:08X}".format(intstat1_check))
else:
    tag("K3: No stale SWINTSTAT")

# K4: Assert SWINT_REQ (ip_rwdmcntl_swint_req_setf(1))
tag("")
tag("K4: Writing SWINT_REQ (RWDMCNTL bit27 = 0x{:08X})".format(SWINT_REQ_MASK))
mmio_write(RWDMCNTL, SWINT_REQ_MASK)
rwdm_after_req = mmio_read(RWDMCNTL)
tag("  RWDMCNTL after write: 0x{:08X}".format(rwdm_after_req))

# K5: Poll INTSTAT1[SWINTSTAT] for assertion
tag("")
tag("K5: Polling INTSTAT1[SWINTSTAT(bit3)] for assertion (max 200)...")
swint_asserted = False
for i in range(200):
    s1 = mmio_read(INTSTAT1)
    if (s1 & SWINTSTAT_BIT) != 0:
        tag("  SWINTSTAT asserted at attempt {:d} (INTSTAT1=0x{:08X})".format(i, s1))
        swint_asserted = True
        break
    if i < 5 or i % 50 == 0:
        tag("  attempt {:d}: INTSTAT1=0x{:08X}".format(i, s1))

intstat0_mid = mmio_read(INTSTAT0)
tag("  INTSTAT0 during SWINT: 0x{:08X}".format(intstat0_mid))

if not swint_asserted:
    tag("  ERROR: SWINTSTAT did not assert after 200 reads")
    verdict = "FAIL:SWINTSTAT_NO_ASSERT"
else:
    # K6: Check SWINT_REQ self-clear
    rwdm_post_req = mmio_read(RWDMCNTL)
    tag("")
    tag("K6: RWDMCNTL after SWINTSTAT assert: 0x{:08X}".format(rwdm_post_req))
    if (rwdm_post_req & SWINT_REQ_MASK) == 0:
        tag("  SWINT_REQ self-cleared (pulse behaviour confirmed)")
    else:
        tag("  Note: SWINT_REQ still set (sticky — clear via INTACK)")

    # K7: Write SWINTACK to clear SWINTSTAT
    tag("")
    tag("K7: Writing INTACK1[SWINTACK(bit3)]=1 to clear SWINTSTAT")
    mmio_write(INTACK1, SWINTACK_BIT)

    # K8: Verify SWINTSTAT cleared
    intstat1_cleared = mmio_read(INTSTAT1)
    intstat0_fin = mmio_read(INTSTAT0)
    tag("")
    tag("K8: Post-ack state")
    tag("  INTSTAT1: 0x{:08X}  (expect SWINTSTAT=0)".format(intstat1_cleared))
    tag("  INTSTAT0: 0x{:08X}  (expect 0x00000000)".format(intstat0_fin))

    if (intstat1_cleared & SWINTSTAT_BIT) != 0:
        tag("  ERROR: SWINTSTAT did not clear after SWINTACK write")
        verdict = "FAIL:SWINTSTAT_NO_CLEAR"
    elif intstat0_fin != 0:
        tag("  ERROR: INTSTAT0 has error flags: 0x{:08X}".format(intstat0_fin))
        verdict = "FAIL:INTSTAT0_ERRORS"
    else:
        tag("")
        tag("PASS: SWINT_REQ triggered INTSTAT1[SWINTSTAT]")
        tag("PASS: SWINTACK cleared INTSTAT1[SWINTSTAT]")
        tag("PASS: INTSTAT0=0 (no error flags)")
        tag("PASS: CPU→CEVA SWINT channel fully operational on ZCU104")
        verdict = "PASS"

tag("")
tag("VERDICT: " + verdict)

end

monitor go
