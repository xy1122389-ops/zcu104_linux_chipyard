# CEVA BT5.2 Phase 0G — Single CEVA Radio/VPHY Activity Report

**RUN_TAG**: `phase0f0g_20260509_211507`  
**Timestamp**: 2026-05-09T14:33:11Z  
**Status**: ✅ **PASS**

---

## 1. Objective

Phase 0G validates that CEVA BT5.2 `RWBLE_EN` (bit 8 of RWBLECNTL at 0x65000400) activates the BLE baseband clock (`blemaster1_gclk`) and that the resulting 3.2kHz CLKN half-slot interrupt (INTSTAT1[0]) fires reliably, confirming the IP is live on the ZCU104 Phase0b bitstream.

---

## 2. Setup

| Item | Value |
|------|-------|
| Bitstream | Phase0b (SHA256=`2054aeff301ed2c04555e8870ffd0b215d181888...`) |
| Baseline | Phase0e-D dm_sw_irq repeated PASS (frozen) |
| CPU state | Alive-heartbeat polling loop (Phase0e completed in sdboot) |
| J-Link | 127.0.0.1:3333, serial=601012542, ZCU104 PMOD0 JTAG |
| GDB script | `scripts/ceva_phase0g_jlink_observe.gdb` |
| Board run script | `scripts/ceva_phase0g_board_run.sh` |
| No bitstream reflash | Used existing Phase0b bitstream on board |

---

## 3. Register Map Used (RTL-Confirmed)

| Register | Address | Field | Bit(s) |
|----------|---------|-------|--------|
| RWBLECNTL | 0x65000400 | RWBLE_EN | bit 8 (mask=0x100) |
| INTCNTL1 | 0x65000018 | CLKNINTMSK | bit 0 |
| INTSTAT0 | 0x6500000C | error flags | — |
| INTSTAT1 | 0x6500001C | CLKNINTSTAT | bit 0 |
| INTACK1 | 0x65000020 | CLKNINTACK | bit 0 |

**RWBLE_EN source**: `rw_ble_reg.v` L2722: `int_rwble_en <= int_reg_dw[8]`  
**RWBLECNTL address**: CEVA DM base 0x65000000 + BLE block offset 0x400

---

## 4. Test Procedure (GDB SBA, non-invasive)

```raw
G1: Read baselines (RWBLECNTL, INTSTAT0, INTCNTL1)
G2: Set INTCNTL1 |= CLKNINTMSK (bit 0)  — unmask CLKN IRQ
G3: ACK stale CLKN IRQ via INTACK1 = 0x1
G4: Write RWBLECNTL = 0x100 (RWBLE_EN = bit 8 = 1)
    Wait 3ms for blemaster1_gclk to start
G5: Poll INTSTAT1[0] until 10 rising edges, ACK each; 3s deadline
G6: Capture INTSTAT0 (error check), hslot_count, final INTSTAT1
G9: Print PASS/FAIL verdict
G10: Clear RWBLE_EN = 0, resume CPU
```

---

## 5. Board Run Results

### Raw GDB Output (key lines)

```raw
0x000000000001008c in ?? ()                     ← CPU halted at sdboot heartbeat
[PHASE0G] G1: RWBLECNTL_before: 0x0000000b     ← initial state (bits set from prior runs)
[PHASE0G] G1: INTSTAT0_before:  0x00000000     ← no DM errors
[PHASE0G] G1: INTCNTL1_before:  0x0000800b     ← prev mask state

Writing 0x0000800B @ address 0x65000018         ← CLKNINTMSK set (already set)
[PHASE0G] G2: INTCNTL1_set:     0x0000800b  (readback: 0x0000800b)

Writing 0x00000001 @ address 0x65000020         ← stale ACK
[PHASE0G] G3: stale CLKN IRQ acked

Writing 0x00000100 @ address 0x65000400         ← RWBLE_EN = bit 8 = 1
[PHASE0G] G4: RWBLECNTL_after:  0x00000100     ← WRITE VERIFIED

[PHASE0G] G5: polling INTSTAT1[CLKNINTSTAT] (need 10 edges in 3s)...
Writing 0x00000001 @ address 0x65000020         ← ACK edge 1
Writing 0x00000001 @ address 0x65000020         ← ACK edge 2
... (×10 total)

[PHASE0G] G6: hslot_count:      0x0000000a  (10 decimal)   ← ≥10 ✅
[PHASE0G] G6: last_intstat1:    0x00000001                  ← IRQ active
[PHASE0G] G6: INTSTAT1_end:     0x00000001                  ← IRQ active
[PHASE0G] G6: INTSTAT0_after:   0x00000000                  ← no errors ✅

[PHASE0G] PASS: CLKN half-slot IRQ confirmed active
[PHASE0G] PASS: RWBLE_EN=1 drives blemaster1_gclk on ZCU104 Phase0b

Writing 0x00000000 @ address 0x65000400         ← RWBLE_EN cleared (standby)
[PHASE0G] CPU resumed
```

### Summary Table

| Check | Expected | Actual | Result |
|-------|----------|--------|--------|
| RWBLECNTL_after | 0x00000100 | 0x00000100 | ✅ PASS |
| INTSTAT0_after | 0x00000000 | 0x00000000 | ✅ PASS |
| hslot_count | ≥ 10 | 10 | ✅ PASS |
| INTSTAT1 active | bit 0 = 1 | 0x00000001 | ✅ PASS |
| Overall | PASS | PASS | ✅ PASS |

---

## 6. Analysis

**RWBLECNTL_before = 0x0000000b**: Bits 0, 1, 3 were set before the test. These are not RWBLE_EN (bit 8). The BLE engine was in its reset/idle state with some config bits pre-loaded. After writing 0x100, only bit 8 was active — confirming the IP accepts clean register writes.

**INTCNTL1_before = 0x0000800b**: Upper bit (0x8000) and bits 0/1/3 pre-set from Phase0e dm_sw_irq test (which had set SWINTMSK etc.). The CLKNINTMSK (bit 0) was already enabled.

**hslot_count = 10 in < 3s**: Each CLKN half-slot is 312.5µs → 10 slots in 3.125ms. With 10ms polling interval, the IRQ fires and stays asserted until ACKed, so we see it immediately. All 10 ACKs were within the 3s window, confirming the BLE clock runs continuously once RWBLE_EN=1.

**INTSTAT0 = 0 throughout**: No DM-level errors. The ExtRC radio interface (`RW_DM_EXTRC_INST`) and timing generator (`RW_DM_TIMING_GEN_LP_EXTERNAL`) did not flag any protocol violations.

---

## 7. Phase 0G PASS Criterion

| Criterion | Status |
|-----------|--------|
| RWBLE_EN write verifiable at 0x65000400 | ✅ 0x00000100 confirmed |
| CLKN IRQ fires ≥ 10 times after RWBLE_EN=1 | ✅ exactly 10 |
| No DM errors (INTSTAT0=0) | ✅ confirmed |
| RWBLE_EN safely clearable (standby restore) | ✅ cleared to 0x0 |

**VERDICT: Phase 0G PASS**

---

## 8. Deferred Items

| Item | Reason Deferred | Unblock Condition |
|------|-----------------|-------------------|
| New bitstream with Phase0g sdboot code | Phase0b generated-src GONE from WSL instance | Recover generated-src from backup or re-run `sbt "runMain chipyard.Generator ..."` |
| sdboot.bin UART test (baremetal.c phase0g_test) | Requires new bitstream (TLROM.sv updated in vivado_build_pkg) | Phase0b bitstream rebuild |
| BT full stack init (HCI, RWBTCNTL, connection) | Deferred to Phase 0H+ | After CLKN IRQ + BT clock verified here |

---

## 9. Next Steps (Phase 0H)

Phase 0G confirms the BLE baseband clock domain is active. Next milestones:

1. **RWBTCNTL**: Write RWBTEN (bit 8 of 0x65000800) → observe BT CLKN via separate IRQ channel
2. **HCI reset command**: Send HCI_Reset (0x0C03) via SPI/UART to CEVA, observe HCI_Command_Complete
3. **Advertising**: Enable BLE advertising and scan with external BT sniffer (Phase 1+)

---

## 10. Files Modified / Created This Session

| File | Change |
|------|--------|
| `src/main/resources/zcu104/sdboot/baremetal.c` | Added `phase0g_test()` function |
| `src/main/resources/zcu104/sdboot/build/sdboot.bin` | Recompiled (PBUS_CLK=100) |
| `vivado_build_pkg/gen-collateral/TLROM.sv` | Updated with Phase0g sdboot content |
| `vivado_build_pkg/gen-collateral/TLROM.sv.bak_phase0e` | Backup of Phase0e TLROM |
| `docs/bringup/ceva_bt52_phase0f_software_init_findings_*.md` | RWBLE_EN=bit8 corrected |
| `docs/bringup/ceva_bt52_phase0g_observability_decision_*.md` | RWBLE_EN=bit8 corrected |
| `docs/bringup/ceva_bt52_phase0g_init_sequence_*.md` | RWBLE_EN=bit8 corrected |
| `scripts/ceva_phase0g_jlink_observe.gdb` | **NEW**: GDB SBA observation script |
| `scripts/ceva_phase0g_board_run.sh` | **NEW**: Board run wrapper script |
| `logs/phase0f0g_20260509_211507/phase0g_observe.log` | Board run log |
| `docs/bringup/ceva_bt52_phase0g_single_ip_activity_report_*.md` | **THIS FILE** |
