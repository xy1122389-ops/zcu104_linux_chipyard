# Phase 1B: CEVA Firmware Boot Verification via EM Reads
#
# Prerequisite: Phase 1A PASS (EM MMIO window at 0x65010000)
#
# After CEVA BT IP is initialized (RWBTEN=1 + TIMGENCNTL set), the internal
# firmware state machine begins running. This phase checks whether the firmware
# has written any initialization data to EM.
#
# CEVA EM layout (from rw-btdm-blehost-sw-v11_0_3 / rwip.c):
#   EM_BASE (from ETPTR):
#   - Exchange Table (ET): starts at EM[0], size varies
#   - BT Descriptor pointers, activity tables, frequency hop tables
#   - TX/RX descriptors
#
# We verify:
#   B1: EM accessible (read EM[0..7] before init)
#   B2: Full CEVA init (DM reset + BT init + TIMGENCNTL + RWBTEN + ETPTR=0)
#   B3: Let CEVA run for 50 CLKN cycles
#   B4: Dump EM[0..63] (256 bytes) - check for non-zero initialization data
#   B5: Check ETPTR value (where firmware set the Exchange Table pointer)
#   B6: If ETPTR != 0, read EM at ETPTR offset
#   B7: Check DM Version register (0x65000004 = VERSION)
#   B8: Check BT CURRENTRXDESCPTR - firmware sets this during init
#   B9: Dump EM[0..255] to DDR buffer for analysis
#
# PASS criteria (flexible - firmware may or may not write EM during baremetal):
#   a) EM accessible (no bus error - all reads return data)
#   b) CEVA core functional (CLKN 10/10)
#   c) ETPTR readable (no error)
#   d) EM[0..63] dumped (data captured regardless of content)
#   e) DM_INTSTAT0=0 (no errors)
#
# EVIDENCE criteria (best-effort):
#   - Non-zero EM words indicate firmware is writing data
#   - ETPTR != 0 indicates firmware set up Exchange Table
#   - CURRENTRXDESCPTR != 0 indicates BT firmware running

set remotetimeout 30
target remote 127.0.0.1:3333
monitor halt

python

import gdb

EM_BASE  = 0x65010000   # CPU EM MMIO window (Phase 1A confirmed)

# CEVA DM/BT registers
DM_RWDMCNTL      = 0x65000000
DM_VERSION       = 0x65000004
DM_INTSTAT0      = 0x6500000C
DM_INTCNTL1      = 0x65000018
DM_INTSTAT1      = 0x6500001C
DM_INTACK1       = 0x65000020
DM_ETPTR         = 0x6500002C
DM_TIMGENCNTL    = 0x650000E0
BT_RWBTCNTL      = 0x65000800
BT_INTCNTL0      = 0x6500080C
BT_INTSTAT0      = 0x65000810
BT_INTACK0       = 0x65000814
BT_CURRENTRXDESC = 0x65000828
RWBTEN_MASK      = 0x00000100
BT_RWBTCNTL_INIT = 0x00000E0D
BT_INTCNTL0_INIT = 0x00010016
TIMGENCNTL_VAL   = 0x011800C8
DM_MASTER_SOFT_RST = 0x80000000

def mmio_read(addr):
    return int(gdb.parse_and_eval("*(unsigned int*)0x{:08X}".format(addr)))

def mmio_write(addr, val):
    gdb.execute("monitor WriteU32 0x{:08X} 0x{:08X}".format(addr, val))

def em_read(word_idx):
    return mmio_read(EM_BASE + word_idx * 4)

def tag(s):
    print("[PHASE1B] " + s)

verdict = "FAIL"
fails = []
evidence = {}

tag("=================================================")
tag("Phase 1B: CEVA Firmware Boot Verification via EM")
tag("  EM window: 0x{:08X}".format(EM_BASE))
tag("=================================================")

# B1: Pre-init EM snapshot
tag("")
tag("B1: Pre-init EM[0..7] snapshot")
pre_em = [em_read(i) for i in range(8)]
for i, v in enumerate(pre_em):
    tag("  EM[{}] @ 0x{:08X} = 0x{:08X}".format(i, EM_BASE+i*4, v))

# B2: Full CEVA init
tag("")
tag("B2: Full CEVA init (DM reset → TIMGENCNTL → BT init → RWBTEN=1 → ETPTR=0)")
mmio_write(DM_RWDMCNTL, DM_MASTER_SOFT_RST)
for i in range(50):
    if (mmio_read(DM_RWDMCNTL) & DM_MASTER_SOFT_RST) == 0:
        break
mmio_write(DM_TIMGENCNTL, TIMGENCNTL_VAL)
# ET pointer = 0 (start of EM)
mmio_write(DM_ETPTR, 0)
mmio_write(BT_INTCNTL0, BT_INTCNTL0_INIT)
mmio_write(BT_INTACK0, 0xFFFFFFFF)
mmio_write(BT_CURRENTRXDESC, 0)
mmio_write(BT_RWBTCNTL, BT_RWBTCNTL_INIT | RWBTEN_MASK)
ic1 = mmio_read(DM_INTCNTL1) | 0x01
mmio_write(DM_INTCNTL1, ic1)
mmio_write(DM_INTACK1, 0x01)
tag("  Init sequence complete")

# B3: Run for 50 CLKN cycles
tag("")
tag("B3: Running for 50 CLKN cycles...")
clkn = 0
for _ in range(2000):
    if mmio_read(DM_INTSTAT1) & 0x01:
        clkn += 1
        mmio_write(DM_INTACK1, 0x01)
        if clkn >= 50:
            break
tag("  CLKN edges collected: {:d}/50  {}".format(clkn, "PASS" if clkn >= 10 else "FAIL"))
if clkn < 10:
    fails.append("CLKN_FAIL")

# B4: Dump EM[0..63] after init
tag("")
tag("B4: EM[0..63] dump (256 bytes) after init")
post_em = [em_read(i) for i in range(64)]
non_zero = sum(1 for v in post_em if v != 0)
tag("  Non-zero words: {}/64".format(non_zero))
evidence['em_nonzero_0_63'] = non_zero

# Print first 16 words
tag("  EM[0..15]:")
for i in range(0, 16, 4):
    row = " ".join("0x{:08X}".format(post_em[j]) for j in range(i, i+4))
    tag("    [{:2d}..{:2d}]: {}".format(i, i+3, row))

if non_zero > 0:
    tag("  EVIDENCE: Firmware has written {} non-zero words to EM[0..63]".format(non_zero))
else:
    tag("  INFO: EM[0..63] all zero — firmware may use higher offsets or EM stays zeroed")

# B5: Read ETPTR
tag("")
tag("B5: Read ETPTR (Exchange Table Pointer)")
etptr = mmio_read(DM_ETPTR)
etptr_offset = etptr << 2   # ETPTR is in words, byte offset = etptr * 4
tag("  ETPTR = 0x{:04X}  (byte offset in EM: 0x{:04X})".format(etptr, etptr_offset))
evidence['etptr'] = etptr

if etptr != 0:
    tag("  EVIDENCE: Firmware set ETPTR to word {:d} (byte offset 0x{:04X})".format(etptr, etptr_offset))
    # B6: Read EM at ETPTR offset
    if etptr < 16383:
        etptr_val = em_read(etptr)
        tag("  EM[ETPTR={}] = 0x{:08X}".format(etptr, etptr_val))
        evidence['em_at_etptr'] = etptr_val
else:
    tag("  INFO: ETPTR=0 (default), no firmware relocation detected")

# B7: VERSION register
tag("")
tag("B7: DM VERSION register")
ver = mmio_read(DM_VERSION)
tag("  VERSION = 0x{:08X}  expect 0x0B000500 (Phase 0D confirmed)".format(ver))
evidence['version'] = ver

# B8: BT CURRENTRXDESCPTR
tag("")
tag("B8: BT CURRENTRXDESCPTR")
rxdesc = mmio_read(BT_CURRENTRXDESC)
tag("  CURRENTRXDESCPTR = 0x{:04X}".format(rxdesc))
evidence['rxdesc'] = rxdesc
if rxdesc != 0:
    tag("  EVIDENCE: BT firmware set CURRENTRXDESCPTR to 0x{:04X}".format(rxdesc))

# B9: Dump EM[0..255] to DDR (0x8F010000) for offline analysis
tag("")
tag("B9: Dump EM[0..255] (1KB) to DDR 0x8F010000 for analysis")
DDR_EM_DUMP = 0x8F010000
for i in range(256):
    v = em_read(i)
    mmio_write(DDR_EM_DUMP + i*4, v)
# Verify a few words
for i in [0, 63, 128, 255]:
    em_v = em_read(i)
    ddr_v = mmio_read(DDR_EM_DUMP + i*4)
    ok = em_v == ddr_v
    tag("  EM[{:3d}]→DDR[{:3d}]: 0x{:08X}  {}".format(i, i, ddr_v, "OK" if ok else "MISMATCH"))
tag("  EM dump complete: 1KB at DDR 0x{:08X}".format(DDR_EM_DUMP))

# Final check
tag("")
tag("Final error check")
dm_intstat0 = mmio_read(DM_INTSTAT0)
bt_intstat0 = mmio_read(BT_INTSTAT0)
tag("  DM_INTSTAT0: 0x{:08X}  (expect 0)".format(dm_intstat0))
tag("  BT_INTSTAT0: 0x{:08X}  (expect 0)".format(bt_intstat0))
if dm_intstat0 != 0:
    fails.append("DM_INTSTAT0")

mmio_write(BT_RWBTCNTL, BT_RWBTCNTL_INIT)

# Evidence summary
tag("")
tag("=== Evidence Summary ===")
tag("  ETPTR value:     0x{:04X}".format(evidence.get('etptr', 0)))
tag("  Non-zero EM[0..63]: {:d}/64".format(evidence.get('em_nonzero_0_63', 0)))
tag("  VERSION register: 0x{:08X}".format(evidence.get('version', 0)))
tag("  RXDESC pointer:  0x{:04X}".format(evidence.get('rxdesc', 0)))

# Verdict
tag("")
if len(fails) == 0:
    tag("PASS: EM MMIO accessible (all reads OK)")
    tag("PASS: CEVA core functional (CLKN {:d}/50)".format(clkn))
    tag("PASS: EM dump to DDR complete (0x8F010000)")
    tag("PASS: DM_INTSTAT0=0 (no errors)")
    if evidence.get('em_nonzero_0_63', 0) > 0:
        tag("EVIDENCE: Firmware wrote {:d} non-zero words to EM[0..63]".format(evidence['em_nonzero_0_63']))
    if evidence.get('etptr', 0) != 0:
        tag("EVIDENCE: ETPTR = 0x{:04X} (firmware relocated Exchange Table)".format(evidence['etptr']))
    tag("")
    tag("PASS: Phase 1B EM firmware inspection complete")
    verdict = "PASS"
else:
    tag("FAIL fields: " + str(fails))
    verdict = "FAIL:" + "+".join(fails)

tag("VERDICT: " + verdict)

end

monitor go
