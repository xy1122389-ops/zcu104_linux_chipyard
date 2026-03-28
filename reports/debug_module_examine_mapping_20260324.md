# ZCU104 Rocket Debug Module Mapping - 2026-03-24

## Goal

This round does **not** target Linux serial output.

The goal is narrower:

1. Explain how `riscv-013 examine()` validates `DTMCS.version`, `abits`, and `idle`.
2. Map those checks to the current Windows `openocd.exe`.
3. Freeze a minimal `DMI` validation sequence for `dmcontrol`, `dmstatus`, `hartinfo`, `abstractcs`.
4. State what success/failure means at each step.

## 1. Source Logic

### 1.1 Generic RISC-V examine entry

Source:
- `/tmp/riscv-openocd-collab/src/target/riscv/riscv.c:2472`

Key logic:
- [`riscv_examine()`](/tmp/riscv-openocd-collab/src/target/riscv/riscv.c:2472) first calls `dtmcs_scan(target->tap, 0, &dtmcontrol)`.
- If `dtmcontrol == 0`, it fails immediately with `"Could not read dtmcontrol"`.
- It then extracts `DTMCONTROL_VERSION` from the low nibble and selects the target-type implementation:
  - `0` -> `riscv-011`
  - `1` -> `riscv-013`

Evidence:
- [riscv.c](/tmp/riscv-openocd-collab/src/target/riscv/riscv.c:2483)
- [riscv.c](/tmp/riscv-openocd-collab/src/target/riscv/riscv.c:2488)
- [riscv.c](/tmp/riscv-openocd-collab/src/target/riscv/riscv.c:2493)

### 1.2 `riscv-013 examine()` DTMCS checks

Source:
- `/tmp/riscv-openocd-collab/src/target/riscv/riscv-013.c:1993`

The check order is:

1. Read `dtmcontrol` via `dtmcs_scan`.
2. Fail if read fails or returns `0`.
3. Require `DTM_DTMCS_VERSION == 1`.
4. Extract:
   - `abits = get_field(dtmcontrol, DTM_DTMCS_ABITS)`
   - `idle = get_field(dtmcontrol, DTM_DTMCS_IDLE)`
5. Fail if `abits > RISCV013_DTMCS_ABITS_MAX`
6. Fail if `abits == 0`
7. Warn only if `abits < RISCV013_DTMCS_ABITS_MIN`
8. Continue into:
   - `check_dbgbase_exists()`
   - `examine_dm()`
   - `dm013_select_target()`
   - `dmstatus_read()`
   - `dm_read(..., DM_HARTINFO)`
   - `dm_read(..., DM_SBCS)`
   - `dm_read(..., DM_ABSTRACTCS)`

Evidence:
- [riscv-013.c](/tmp/riscv-openocd-collab/src/target/riscv/riscv-013.c:2003)
- [riscv-013.c](/tmp/riscv-openocd-collab/src/target/riscv/riscv-013.c:2012)
- [riscv-013.c](/tmp/riscv-openocd-collab/src/target/riscv/riscv-013.c:2021)
- [riscv-013.c](/tmp/riscv-openocd-collab/src/target/riscv/riscv-013.c:2024)
- [riscv-013.c](/tmp/riscv-openocd-collab/src/target/riscv/riscv-013.c:2033)
- [riscv-013.c](/tmp/riscv-openocd-collab/src/target/riscv/riscv-013.c:2038)
- [riscv-013.c](/tmp/riscv-openocd-collab/src/target/riscv/riscv-013.c:2069)
- [riscv-013.c](/tmp/riscv-openocd-collab/src/target/riscv/riscv-013.c:2079)
- [riscv-013.c](/tmp/riscv-openocd-collab/src/target/riscv/riscv-013.c:2094)
- [riscv-013.c](/tmp/riscv-openocd-collab/src/target/riscv/riscv-013.c:2098)

### 1.3 Relevant field definitions

Source:
- `/tmp/riscv-openocd-collab/src/target/riscv/debug_defines.h`

Important `DTMCS` fields:
- `VERSION`: bits `3:0`
- `ABITS`: bits `9:4`
- `DMISTAT`: bits `11:10`
- `IDLE`: bits `14:12`

Important `DM` addresses:
- `DMCONTROL = 0x10`
- `DMSTATUS = 0x11`
- `HARTINFO = 0x12`
- `ABSTRACTCS = 0x16`

Evidence:
- [debug_defines.h](/tmp/riscv-openocd-collab/src/target/riscv/debug_defines.h:102)
- [debug_defines.h](/tmp/riscv-openocd-collab/src/target/riscv/debug_defines.h:114)
- [debug_defines.h](/tmp/riscv-openocd-collab/src/target/riscv/debug_defines.h:117)
- [debug_defines.h](/tmp/riscv-openocd-collab/src/target/riscv/debug_defines.h:2068)
- [debug_defines.h](/tmp/riscv-openocd-collab/src/target/riscv/debug_defines.h:1870)
- [debug_defines.h](/tmp/riscv-openocd-collab/src/target/riscv/debug_defines.h:2266)
- [debug_defines.h](/tmp/riscv-openocd-collab/src/target/riscv/debug_defines.h:2328)

## 2. Windows Binary Mapping

Binary under test:
- `/tmp/riscv-collab-openocd/bin/openocd.exe`

### 2.1 Proven first shift point: `dtmcs_scan_via_bscan()`

Local symbolized object:
- `dtmcs_scan_via_bscan` at [riscv.o](/root/chipyard/fpga/tmp-openocd-work/src/target/riscv/riscv.o)

Local symbolized logic:
- [riscv.o dtmcs_scan_via_bscan](/root/chipyard/fpga/tmp-openocd-work/src/target/riscv/riscv.o)
  shows the returned 33-bit tunneled DR payload being unpacked after `jtag_execute_queue()`.

Windows binary mapping:
- `0x483cad`: `mov $0x1,%edx`
- followed by the bit unpack loop that reconstructs the returned `DTMCS`

Evidence:
- local object equivalent at [riscv.o](/root/chipyard/fpga/tmp-openocd-work/src/target/riscv/riscv.o)
- Windows disassembly:
  - `0x483cad` in `/tmp/openocd_collab.dis`
  - verified with:
    - `objdump --start-address=0x483c90 --stop-address=0x483ce5`

Why this matters:
- This is the first confirmed place where the current Windows binary assumes a one-bit skew.
- A local experiment changing this constant from `1` to `2` changed the first returned `DTMCS` from `0xf768e3f1` to `0xf768e3f0`, proving this site is live.
- It did **not** fix the overall path, so this is only one of the required decode points.

### 2.2 Generic `riscv_examine()` logging/branch points

Windows binary addresses tied to generic `riscv_examine()`:
- `0x483fde` -> `"version=0x%x"`
- `0x48401c` -> `"Could not read dtmcontrol. Check JTAG connectivity/board power."`

Evidence:
- strings extracted from `openocd.exe`
- address references in `/tmp/openocd_collab.dis`

Meaning:
- This is the outer generic RISC-V target selection logic.
- It decides whether the target falls into `riscv-011` or `riscv-013`.

### 2.3 `riscv-013 examine()` validation branches

Windows binary region:
- around `0x5cab2c .. 0x5cb5dc`

Useful branch/message anchors:
- `0x5cb381` -> `"Unsupported DTM version %u. (dtmcontrol=0x%x)"`
- `0x5cb52e` -> `"dtmcs.abits is zero. Check JTAG connectivity/board power"`
- `0x5cb5ac` -> `"found dtmcs.abits = %d; minimum is abits = %d."`

Evidence:
- string references at:
  - `0x87eb4c`
  - `0x87ec00`
  - `0x87ebc8`
- corresponding code addresses in `/tmp/openocd_collab.dis`

Meaning:
- These are the exact Windows-side branches enforcing the same logic as source lines:
  - [riscv-013.c:2012](/tmp/riscv-openocd-collab/src/target/riscv/riscv-013.c:2012)
  - [riscv-013.c:2033](/tmp/riscv-openocd-collab/src/target/riscv/riscv-013.c:2033)
  - [riscv-013.c:2038](/tmp/riscv-openocd-collab/src/target/riscv/riscv-013.c:2038)

### 2.4 Proven second shift site in source, narrowed in Windows binary

Local symbolized source/object:
- `riscv_batch_run_from()` in [batch.o](/root/chipyard/fpga/tmp-openocd-work/src/target/riscv/batch.o)
- original source uses:
  - `buffer_shr((batch->fields + i)->in_value, DMI_SCAN_BUF_SIZE, 1);`
- patched local source currently uses:
  - `buffer_shr(..., DMI_SCAN_BUF_SIZE, 2);`

Local proof:
- original 64-bit object:
  - `0x895: mov $0x1,%edx`
  - `0x89a: mov $0xd,%esi`
  - `call buffer_shr`
- patched 64-bit object:
  - `0x895: mov $0x2,%edx`

Meaning:
- This is the second independent place where returned BSCAN/DMI payload is shifted after queue execution.
- The exact matching Windows callsite has been narrowed to the `batch` post-processing region, but it has **not yet been conclusively binary-patched** in this round.

## 3. Minimal DMI Validation Sequence

Script added:
- [manual_dmi_minimal_validation.sh](/root/chipyard/fpga/scripts/manual_dmi_minimal_validation.sh)

Latest reproducible logs:
- [manual_dmi_minimal_validation_20260324_125516](/root/chipyard/fpga/logs/manual_dmi_minimal_validation_20260324_125516)

The fixed sequence is:

1. Bring up the current debug bit.
2. Use `outer IR = 0x926`, `Nested tunnel`, width `5`.
3. Select DBUS once:
   - `drscan uscale.ps 1 0 7 0x05 5 0x11 3 0`
4. For each target DMI address, issue a single read request:
   - `dmcontrol @ 0x10`
   - `dmstatus @ 0x11`
   - `hartinfo @ 0x12`
   - `abstractcs @ 0x16`
5. For write validation, issue `DMCONTROL` writes:
   - `dmactive = 1`
   - `haltreq = 1`
6. After each request, collect `NOP1/NOP2/NOP3` follow-ups.

## 4. What Success / Failure Means

### Step A: `DTMCS` probe via `riscv-collab + 0x926 + Nested`

Success means:
- First `DTMCS` read gives `version = 1`
- second `DTMCS` decode yields sane `abits` and `idle`
- target advances past `Unsupported DTM version`

Current result:
- first `DTMCS` is still the strongest evidence path:
  - `0xf768e3f1`
  - `version = 0x1`
- second decode still becomes malformed:
  - `0xf7ffe300`
  - `version = 0`
  - `abits = 0x30`

Evidence:
- [openocd_probe_riscv_collab_ir_926_t0_20260324_120953](/root/chipyard/fpga/logs/openocd_probe_riscv_collab_ir_926_t0_20260324_120953)

Interpretation:
- `debug module reachability` is **partially confirmed**
- `semantic DTM/DM decoding` is **not yet confirmed**

### Step B: single-register `DMI` reads

Success means:
- `REQ @ 0x10 / 0x11 / 0x12 / 0x16` produce distinguishable raw responses
- follow-up `NOP` packets stabilize to different values by address
- that would prove the address field is preserved through the tunnel

Current result:
- `dmcontrol / dmstatus / hartinfo / abstractcs` all collapse to the **same raw packet sequence**
- address-specific meaning is therefore not recoverable yet

Evidence:
- [manual_dmi_minimal_validation_20260324_125516](/root/chipyard/fpga/logs/manual_dmi_minimal_validation_20260324_125516)

Interpretation:
- Current tunnel path is **not yet preserving decodable DMI address semantics**
- We do **not** yet have a trustworthy `dmstatus/hartinfo/abstractcs` read

### Step C: `DMCONTROL` write probes

Success means:
- writing `dmactive`, `haltreq`, `resumereq`, `ndmreset`, `hartreset`, or `ackhavereset`
  should change follow-up raw packets in a stable and field-consistent way

Current result:
- Earlier wider experiments showed only slight nibble-level perturbation for some writes
- In the fixed minimal script, even `dmactive` vs `haltreq` currently collapse to the same write packet family

Evidence:
- [manual_dmi_minimal_validation_20260324_125516](/root/chipyard/fpga/logs/manual_dmi_minimal_validation_20260324_125516)

Interpretation:
- We do **not** yet have proof that the hart/debug control bits are being interpreted correctly by the target
- Therefore `debug module usable for hart control` is still **unconfirmed**

## 5. Round Conclusion

### Confirmed
- The `debug + BSCAN` bitstream path is active enough to expose a live tunneled path.
- `outer IR = 0x926`, `Nested tunnel`, width `5` is still the strongest current route.
- Generic `DTMCS` probing reaches a first-frame `version = 1`.
- `riscv-013 examine()` source logic and the Windows binary branches enforcing `version/abits` checks have now been mapped.
- `manual_dmi_minimal_validation.sh` produces a stable, reproducible minimal validation log set.

### Excluded
- This round did **not** support the hypothesis that the problem is simply "OpenOCD version too low".
- It also did **not** support the hypothesis that `dmcontrol/dmstatus/hartinfo/abstractcs` are already semantically readable through the current tunnel.

### Unknown
- The exact second Windows binary patch site corresponding to post-queue `buffer_shr(..., 1)` is narrowed but not yet conclusively patched.
- Whether the remaining error is:
  - a second unpatched shift,
  - a BSCAN packet packing mismatch,
  - or a tunnel-mode-specific field-width mismatch,
  is still unresolved.

## Next Step

The next highest-value step is:

1. Patch the **second** Windows-side post-processing shift in the `batch` path.
2. Re-run the same fixed validation set:
   - `DTMCS`
   - `dmcontrol`
   - `dmstatus`
   - `hartinfo`
   - `abstractcs`
3. Only if those become distinguishable and sane, move on to `hart halt/pc` capture.
