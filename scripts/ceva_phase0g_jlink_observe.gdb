# Phase 0G: BLE RWBLE_EN + CLKN half-slot interrupt observation
# Run via: ceva_phase0g_board_run.sh (which wraps GDB -batch -x this_file)
#
# Hardware context:
#   Bitstream: RocketZCU104Phase0bConfig (Phase0e-D confirmed PASS at sha256=2054aeff)
#   CPU state: alive-heartbeat polling loop (Phase0e irq test already completed)
#   CEVA base: 0x65000000
#
# Register map (from RTL confirmed):
#   INTCNTL1:  0x65000018  CLKNINTMSK = bit 0
#   INTSTAT0:  0x6500000c  error flags
#   INTSTAT1:  0x6500001c  CLKNINTSTAT = bit 0, SWINTSTAT = bit 3
#   INTACK1:   0x65000020  CLKNINTACK = bit 0
#   RWBLECNTL: 0x65000400  RWBLE_EN = bit 8 (mask=0x100) -- RTL confirmed

set remotetimeout 30
target remote 127.0.0.1:3333
monitor halt

python
import time

# -------- helpers --------
def jl_read(addr):
    """SBA read via GDB *(unsigned int*) — ReadU32 not supported by J-Link GDBServer."""
    try:
        val = gdb.parse_and_eval("*(unsigned int*)0x{:08x}".format(addr))
        return int(val) & 0xFFFFFFFF
    except gdb.error as e:
        print("[PHASE0G] WARN: jl_read(0x{:08x}) error: {}".format(addr, e))
        return None

def jl_write(addr, val):
    """SBA write via J-Link monitor WriteU32."""
    gdb.execute("monitor WriteU32 0x{:08x} 0x{:08x}".format(addr, val))

# -------- constants --------
CEVA_BASE   = 0x65000000
INTSTAT0    = CEVA_BASE + 0x00C   # DM error flags
INTCNTL1    = CEVA_BASE + 0x018   # DM interrupt mask 1
INTSTAT1    = CEVA_BASE + 0x01C   # DM interrupt status 1
INTACK1     = CEVA_BASE + 0x020   # DM interrupt ack 1
RWBLECNTL   = CEVA_BASE + 0x400   # BLE block RWBLECNTL, RWBLE_EN=bit8

CLKNINTMSK  = 0x1    # INTCNTL1 bit 0
CLKNINTSTAT = 0x1    # INTSTAT1 bit 0
CLKNINTACK  = 0x1    # INTACK1  bit 0
RWBLE_EN    = 0x100  # RWBLECNTL bit 8

MIN_HSLOT   = 10     # need >= 10 CLKN edges for PASS
POLL_SECS   = 3.0    # max poll window (3s >> 10*312.5µs = 3.125ms)

print("[PHASE0G] ============================================")
print("[PHASE0G] Phase 0G: BLE RWBLE_EN + CLKN observation")
print("[PHASE0G] Using existing Phase0b bitstream (no reflash)")
print("[PHASE0G] ============================================")

# -------- G1: baseline reads --------
ble_before   = jl_read(RWBLECNTL)
int0_before  = jl_read(INTSTAT0)
intcntl1_cur = jl_read(INTCNTL1)

print("[PHASE0G] G1: RWBLECNTL_before: 0x{:08x}".format(ble_before   or 0))
print("[PHASE0G] G1: INTSTAT0_before:  0x{:08x}".format(int0_before  or 0))
print("[PHASE0G] G1: INTCNTL1_before:  0x{:08x}".format(intcntl1_cur or 0))

# -------- G2: enable CLKN interrupt mask --------
new_intcntl1 = (intcntl1_cur or 0) | CLKNINTMSK
jl_write(INTCNTL1, new_intcntl1)
time.sleep(0.001)
intcntl1_readback = jl_read(INTCNTL1)
print("[PHASE0G] G2: INTCNTL1_set:     0x{:08x}  (readback: 0x{:08x})".format(
    new_intcntl1, intcntl1_readback or 0))

# -------- G3: ACK stale CLKN interrupt --------
jl_write(INTACK1, CLKNINTACK)
time.sleep(0.001)
print("[PHASE0G] G3: stale CLKN IRQ acked")

# -------- G4: set RWBLE_EN = bit 8 = 1 --------
jl_write(RWBLECNTL, RWBLE_EN)
time.sleep(0.003)   # 3ms: allow blemaster1_gclk to start, first CLKN to arrive

ble_after = jl_read(RWBLECNTL)
print("[PHASE0G] G4: RWBLECNTL_after:  0x{:08x}".format(ble_after or 0))

if ble_after is None or (ble_after & RWBLE_EN) == 0:
    print("[PHASE0G] FAIL: rwble_en_not_set (addr=0x{:08x} readback=0x{:08x})".format(
        RWBLECNTL, ble_after or 0))
    # Restore and exit
    jl_write(RWBLECNTL, 0x0)
    gdb.execute("monitor go")
else:
    # -------- G5: poll INTSTAT1[CLKNINTSTAT] for >= 10 edges --------
    hslot_count = 0
    last_intstat1 = 0
    deadline = time.time() + POLL_SECS

    print("[PHASE0G] G5: polling INTSTAT1[CLKNINTSTAT] (need {} edges in {:.0f}s)...".format(
        MIN_HSLOT, POLL_SECS))

    while hslot_count < MIN_HSLOT and time.time() < deadline:
        intstat1 = jl_read(INTSTAT1)
        if intstat1 is None:
            continue
        last_intstat1 = intstat1
        if (intstat1 & CLKNINTSTAT) != 0:
            # ACK this edge
            jl_write(INTACK1, CLKNINTACK)
            hslot_count += 1
        time.sleep(0.010)   # 10ms per poll; CLKN fires every 312.5µs (sticky bit)

    # -------- G6: capture final status --------
    int0_after   = jl_read(INTSTAT0)
    intstat1_end = jl_read(INTSTAT1)

    print("[PHASE0G] G6: hslot_count:      0x{:08x}  ({} decimal)".format(hslot_count, hslot_count))
    print("[PHASE0G] G6: last_intstat1:    0x{:08x}".format(last_intstat1))
    print("[PHASE0G] G6: INTSTAT1_end:     0x{:08x}".format(intstat1_end or 0))
    print("[PHASE0G] G6: INTSTAT0_after:   0x{:08x}".format(int0_after  or 0))

    # -------- G7: verdict --------
    if hslot_count >= MIN_HSLOT:
        print("[PHASE0G] PASS: CLKN half-slot IRQ confirmed active")
        print("[PHASE0G] PASS: RWBLE_EN=1 drives blemaster1_gclk on ZCU104 Phase0b")
    else:
        print("[PHASE0G] FAIL: hslot_count_low ({}/{})".format(hslot_count, MIN_HSLOT))
        if int0_after and int0_after != 0:
            print("[PHASE0G] FAIL: INTSTAT0 errors present: 0x{:08x}".format(int0_after))

    # -------- G8: clear RWBLE_EN and resume --------
    jl_write(RWBLECNTL, 0x0)
    print("[PHASE0G] RWBLE_EN cleared (returned to standby)")
    gdb.execute("monitor go")
    print("[PHASE0G] CPU resumed")
end
detach
quit
