# Phase 0H: BT RWBTEN + CLKN half-slot interrupt observation
# Run via: ceva_phase0h_board_run.sh
#
# Hardware context:
#   Bitstream: RocketZCU104Phase0bConfig (Phase0e-D, Phase0g PASS)
#   CPU state: alive-heartbeat polling loop
#   CEVA base: 0x65000000
#
# RTL confirmed (rw_bt_reg.v L3700):
#   RWBTCNTL:  0x65000800  RWBTEN = bit 8 (mask=0x100)
#   clknint is a SINGLE signal shared by BLE+BT (rw_dm_int_cntl.v L49)
#   Therefore INTSTAT1[0] (CLKNINTSTAT) fires for BOTH BLE and BT CLKN

set remotetimeout 30
target remote 127.0.0.1:3333
monitor halt

python
import time

def jl_read(addr):
    try:
        val = gdb.parse_and_eval("*(unsigned int*)0x{:08x}".format(addr))
        return int(val) & 0xFFFFFFFF
    except gdb.error as e:
        print("[PHASE0H] WARN: jl_read(0x{:08x}) error: {}".format(addr, e))
        return None

def jl_write(addr, val):
    gdb.execute("monitor WriteU32 0x{:08x} 0x{:08x}".format(addr, val))

# -------- constants --------
CEVA_BASE   = 0x65000000
INTSTAT0    = CEVA_BASE + 0x00C
INTCNTL1    = CEVA_BASE + 0x018
INTSTAT1    = CEVA_BASE + 0x01C
INTACK1     = CEVA_BASE + 0x020
RWBLECNTL   = CEVA_BASE + 0x400   # BLE: ensure cleared
RWBTCNTL    = CEVA_BASE + 0x800   # BT:  RWBTEN = bit 8

CLKNINTMSK  = 0x1
CLKNINTSTAT = 0x1
CLKNINTACK  = 0x1
RWBTEN      = 0x100   # bit 8, RTL confirmed

MIN_HSLOT   = 10
POLL_SECS   = 3.0

print("[PHASE0H] ============================================")
print("[PHASE0H] Phase 0H: BT RWBTEN + CLKN observation")
print("[PHASE0H] Using existing Phase0b bitstream (no reflash)")
print("[PHASE0H] ============================================")

# H1: ensure RWBLECNTL cleared (Phase0G already did this, verify)
ble_check = jl_read(RWBLECNTL)
print("[PHASE0H] H1: RWBLECNTL_check: 0x{:08x}  (must be 0 for clean BT-only test)".format(ble_check or 0))
if ble_check and (ble_check & 0x100) != 0:
    jl_write(RWBLECNTL, 0x0)
    print("[PHASE0H] H1: RWBLECNTL cleared (was set from prior run)")

# H2: baseline reads
bt_before    = jl_read(RWBTCNTL)
int0_before  = jl_read(INTSTAT0)
intcntl1_cur = jl_read(INTCNTL1)
print("[PHASE0H] H2: RWBTCNTL_before:  0x{:08x}".format(bt_before    or 0))
print("[PHASE0H] H2: INTSTAT0_before:  0x{:08x}".format(int0_before  or 0))
print("[PHASE0H] H2: INTCNTL1_before:  0x{:08x}".format(intcntl1_cur or 0))

# H3: enable CLKN mask + ACK stale
new_intcntl1 = (intcntl1_cur or 0) | CLKNINTMSK
jl_write(INTCNTL1, new_intcntl1)
jl_write(INTACK1, CLKNINTACK)
time.sleep(0.001)
print("[PHASE0H] H3: INTCNTL1_set: 0x{:08x}  stale ACK done".format(new_intcntl1))

# H4: set RWBTEN = bit 8 = 1
jl_write(RWBTCNTL, RWBTEN)
time.sleep(0.003)
bt_after = jl_read(RWBTCNTL)
print("[PHASE0H] H4: RWBTCNTL_after:   0x{:08x}".format(bt_after or 0))

if bt_after is None or (bt_after & RWBTEN) == 0:
    print("[PHASE0H] FAIL: rwbten_not_set (addr=0x{:08x} readback=0x{:08x})".format(
        RWBTCNTL, bt_after or 0))
    jl_write(RWBTCNTL, 0x0)
    gdb.execute("monitor go")
else:
    # H5: poll INTSTAT1[0] for >= 10 edges
    hslot_count = 0
    last_intstat1 = 0
    deadline = time.time() + POLL_SECS

    print("[PHASE0H] H5: polling INTSTAT1[CLKNINTSTAT] (need {} edges in {:.0f}s)...".format(
        MIN_HSLOT, POLL_SECS))

    while hslot_count < MIN_HSLOT and time.time() < deadline:
        intstat1 = jl_read(INTSTAT1)
        if intstat1 is None:
            continue
        last_intstat1 = intstat1
        if (intstat1 & CLKNINTSTAT) != 0:
            jl_write(INTACK1, CLKNINTACK)
            hslot_count += 1
        time.sleep(0.010)

    # H6: capture final status
    int0_after   = jl_read(INTSTAT0)
    intstat1_end = jl_read(INTSTAT1)

    print("[PHASE0H] H6: hslot_count:      0x{:08x}  ({} decimal)".format(hslot_count, hslot_count))
    print("[PHASE0H] H6: last_intstat1:    0x{:08x}".format(last_intstat1))
    print("[PHASE0H] H6: INTSTAT1_end:     0x{:08x}".format(intstat1_end or 0))
    print("[PHASE0H] H6: INTSTAT0_after:   0x{:08x}".format(int0_after  or 0))

    if hslot_count >= MIN_HSLOT:
        print("[PHASE0H] PASS: BT CLKN half-slot IRQ confirmed active")
        print("[PHASE0H] PASS: RWBTEN=1 drives btmaster1_gclk on ZCU104 Phase0b")
    else:
        print("[PHASE0H] FAIL: hslot_count_low ({}/{})".format(hslot_count, MIN_HSLOT))
        if int0_after and int0_after != 0:
            print("[PHASE0H] FAIL: INTSTAT0 errors: 0x{:08x}".format(int0_after))

    # H7: clear RWBTEN and resume
    jl_write(RWBTCNTL, 0x0)
    print("[PHASE0H] RWBTEN cleared (returned to standby)")
    gdb.execute("monitor go")
    print("[PHASE0H] CPU resumed")
end
detach
quit
