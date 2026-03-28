# `sw5` JTAGTUNNEL DMI Semantics Summary

Date: `2026-03-26`

## Fixed Baseline
- Window: `shiftCounter <= posCounter <= 42` via `sw5 = 36..42`
- ILA artifact:
  - [jtagtunnel_ila_20260326_213703](/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig/debug_obj/jtagtunnel_ila_20260326_213703)
- Capture path:
  - [capture_jtagtunnel_ila_inline_clean.sh](/root/chipyard/fpga/scripts/capture_jtagtunnel_ila_inline_clean.sh)
  - [capture_jtagtunnel_ila_inline_stim.sh](/root/chipyard/fpga/scripts/capture_jtagtunnel_ila_inline_stim.sh)
  - [capture_jtagtunnel_ila_inline_xsdbseq.sh](/root/chipyard/fpga/scripts/capture_jtagtunnel_ila_inline_xsdbseq.sh)
  - [capture_jtagtunnel_ila_inline_dmi_minimal.sh](/root/chipyard/fpga/scripts/capture_jtagtunnel_ila_inline_dmi_minimal.sh)
  - [capture_jtagtunnel_ila_inline_dmcontrol_case.sh](/root/chipyard/fpga/scripts/capture_jtagtunnel_ila_inline_dmcontrol_case.sh)

## Primary Window Result
- `allzeros`:
  - [allzeros_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_allzeros_sw5_20260326_215033)
- `bit1`:
  - [bit1_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_bit1_sw5_20260326_215202)
- `w5`:
  - [w5_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_w5_sw5_20260326_215349)
  - [w5_sw5_repeat](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_w5_sw5_repeat_20260326_215751)
- `w8`:
  - [w8_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_w8_sw5_20260326_215534)

### Confirmed
- `w5` is no longer in the same event-value class as `allzeros / bit1 / w8`.
- `w8` remains in the same class as `allzeros`.
- This is the first window where `w5` consistently leaves the `allzeros/w8` family.

### Not yet fully stable
- `w5` repeat is still not byte-for-byte identical to the first `w5` capture.
- The repeat remains much closer to the first `w5` than to pure `allzeros`, but exact class identity still shows drift.

## DMI Address Probe with `SELECT_PAYLOAD=0x10`

### Captures
- `0x10`:
  - [dmi10s10_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_dmi10s10_sw5_20260326_220709)
  - [dmi10s10_sw5_repeat](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_dmi10s10_sw5_repeat_20260326_222120)
- `0x11`:
  - [dmi11s10_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_dmi11s10_sw5_20260326_220913)
- `0x12`:
  - [dmi12s10_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_dmi12s10_sw5_20260326_221123)
- `0x16`:
  - [dmi16s10_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_dmi16s10_sw5_20260326_221328)
  - [dmi16s10_sw5_repeat](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_dmi16s10_sw5_repeat_20260326_222433)
- `0x40`:
  - [haltreq_a40_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_haltreq_a40_sw5_20260326_225547)

### Confirmed
- `0x11` remains in the `allzeros` class.
- `0x10` leaves the `allzeros` class, and this remains true on immediate repeat.
- `0x16` also leaves the `allzeros` class, and this remains true on immediate repeat.
- Therefore, address semantics are no longer fully collapsed at `sw5`.

### Still unstable
- `0x10` and `0x16` do not reproduce as byte-for-byte identical event sequences on repeat, but both stay far closer to their own first capture than to pure `allzeros`.
- `0x12` differs from `allzeros`, but the first difference occurs much later and currently looks weaker than `0x10` or `0x16`.
- Current grouping is best described as:
  - `allzeros / w8 / dmi11 / dmactive / haltreq`
  - `dmi10`
  - `dmi16`
  - `w5`
- `0x40` does not leave the `allzeros` family on its own, so it is not yet a useful hart-state discriminator on the current tunnel view.

## DMCONTROL Cases
- `dmactive`:
  - [dmactive_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_dmactive_sw5_20260326_221636)
- `haltreq`:
  - [haltreq_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_haltreq_sw5_20260326_221845)
- `dmactive`, read back `dmcontrol` only:
  - [dmactive_dmc_only_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_dmactive_dmc_only_sw5_20260326_223629)
- `haltreq`, read back `dmcontrol` only:
  - [haltreq_dmc_only_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_haltreq_dmc_only_sw5_20260326_223821)
- `dmactive`, read back `dmcontrol + dmstatus`:
  - [dmactive_rb_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_dmactive_rb_sw5_20260326_222833)
- `haltreq`, read back `dmcontrol + dmstatus`:
  - [haltreq_rb_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_haltreq_rb_sw5_20260326_223055)
  - [haltreq_rb_sw5_repeat](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_haltreq_rb_sw5_repeat_20260326_223319)

### Confirmed
- Current `dmactive` and `haltreq` probe sequences still collapse back into the `allzeros` family.
- So at this stage, `dmcontrol -> dmstatus` semantics are not yet stably recoverable.

### New confirmed nuance
- `dmactive` + `read dmcontrol` leaves the `allzeros` family.
- `haltreq` + `read dmcontrol` still collapses into `allzeros`.
- `dmactive` + `read dmcontrol + dmstatus` collapses back into `allzeros`.
- `haltreq` + `read dmcontrol + dmstatus` leaves the `allzeros` family, and this remains true on immediate repeat.

### Current interpretation
- `sw5` is now showing partial, order-sensitive hart-control semantics.
- The strongest current distinction is no longer just by DMI address; it also depends on control sequence ordering:
  - `read dmcontrol` is sensitive to `dmactive`
  - adding `read dmstatus` after `haltreq` creates a new stable family
- This is still not enough to call `dmstatus` fully trustworthy, but it is beyond the earlier “everything collapses to one family” state.

## Control-Reversal Result

### Captures
- `resumereq + read dmstatus`:
  - [resumereq_a11_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_resumereq_a11_sw5_20260326_225821)
- `haltreq -> resumereq -> read dmstatus`:
  - [haltreq_then_resumereq_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_haltreq_then_resumereq_sw5_20260326_230117)
- `haltreq -> dmactive -> read dmstatus`:
  - [haltreq_then_dmactive_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_haltreq_then_dmactive_sw5_20260326_230342)
- `haltreq -> resumereq -> read 0x40`:
  - [haltreq_then_resumereq_a40_sw5](/root/chipyard/fpga/logs/jtagtunnel_ila_inline_haltreq_then_resumereq_a40_sw5_20260326_230728)

### Confirmed
- `resumereq + read dmstatus` collapses into the `allzeros` family.
- `haltreq -> resumereq -> read dmstatus` also collapses into the `allzeros` family.
- `haltreq -> dmactive -> read dmstatus` also collapses into the `allzeros` family.
- `haltreq -> resumereq -> read 0x40` also collapses into the `allzeros` family.

### Strong interpretation
- The `haltreq-family` is not just “another random class”.
- It is now reversible by follow-up control writes:
  - `haltreq` creates the new family
  - `resumereq` or a follow-up `dmactive` write pulls the sequence back to `allzeros`
- That is the strongest evidence so far that `sw5` is carrying real control semantics rather than accidental packet-shape differences.
- The current strongest control-sensitive read family is still concentrated around `0x11/0x12/0x16`; `0x40` does not participate.

## Net Result
- `sw5` is useful enough to freeze for now.
- The search has crossed the threshold from “no address semantics at all” to “partial address separation is visible”.
- `0x10` and `0x16` are now the strongest address-separation signals on this window.
- But the capture chain is still not stable enough to declare `dmcontrol / dmstatus / hartinfo / abstractcs` fully trustworthy.

## Recommended next step
- Keep `sw5` fixed.
- Use `sw5` as the fixed debug window and move the next round to hart-control semantics:
  - `dmcontrol dmactive`
  - `dmcontrol haltreq`
  - any minimal hart-state query path that can be framed through the same capture method
- Prioritize queries that can expose hart state through the same ordered sequence style, instead of moving the window again.
- In particular, the next best target is a hart-state style query that should differ between:
  - `allzeros`
  - `haltreq-family`
  - `haltreq -> resumereq`
- Do not move to `sw6` unless `0x10/0x16` collapse again.

## Progbuf Instruction-Content Sensitivity

### Confirmed families
- `allzeros-family`
  - `nop = 0x00000013`
  - `ecall = 0x00000073`
  - `addi x1, x0, 1 = 0x00100093`
  - `slti x0, x0, 1 = 0x00102013`
  - `csrrs x0, dcsr, x0 = 0x7b002073`
  - `csrrs x1, dcsr, x0 = 0x7b0020f3`
- `addi-x0-1 family`
  - `addi x0, x0, 1 = 0x00100013`
- `ebreak-family`
  - `ebreak = 0x00100073`

### Hard interpretation
- `progbuf` execution is no longer collapsing to a single packet-shape family.
- The current tunnel view is sensitive to exact instruction encodings, not just to coarse categories such as “has side effect” or “is CSR”.
- This is the strongest hart-side evidence so far beyond pure `dmcontrol/haltreq` sequencing.

## `addi x0, x0, imm` Family Map

Authoritative family map log:
- [addi_x0_family_map_20260327_1400.log](/root/chipyard/fpga/logs/addi_x0_family_map_20260327_1400.log)

Current stable classes:
- `allzeros`
  - `0`
- `main`
  - `1, 18, 19, 39, 40, 41(recheck), 42, 43, 44, 45, 46(recheck), 47, 48, 49, 51, 52, 54, 55, 56, 57, 59, 60, 61, 62`
- `fam4_26`
  - `4, 26`
- `fam15`
  - `15`
- `fam20_29`
  - `20, 29`
- `fam22`
  - `22`
- `fam23_28`
  - `23, 28`
- `fam32`
  - `32`
- `fam33`
  - `33`
- `fam37`
  - `37`
- `fam38`
  - `38`
- `fam63`
  - `63`

New high-range outliers that are now confirmed from the first pass:
- `50` is not in `main`
- `53` is not in `main`
- `58` is not in `main`

### Hard interpretation
- The `addi imm` response is not a simple “bit20 set vs unset” partition.
- By `sw5`, the tunnel view has become sensitive to several sparse and repeatable encoding islands.
- High-range immediates mostly fall back into `main`, but there are still isolated outliers (`50`, `53`, `58`, `63`) that need one clean recheck each before treating them as permanently stable families.

## High-Range Recheck Update

Recheck results:
- `50`
  - first pass was a unique high-range outlier
  - recheck fell into `fam4_26`
- `53`
  - first pass was a unique high-range outlier
  - recheck fell back into `main`
- `58`
  - first pass produced a unique high-range outlier
  - recheck produced a *different* unique family again, not matching `main` or the first-pass `58`

### Updated interpretation
- `50` is no longer a stable new family candidate.
- `53` is no longer a stable new family candidate.
- `58` is still unstable, but not yet promotable to a trustworthy family because the repeat did not land in the same class.
- This means the genuinely stable high-range exceptions are still concentrated in:
  - `15`
  - `20/29`
  - `22`
  - `23/28`
  - `32`
  - `33`
  - `37`
  - `38`
  - `63`
- After this point, the highest-value cleanup is to recheck `37` and `38`, not to keep extending the high-range scan.

## `rd=x1` Addi Contrast

Minimal `addi x1, x0, imm` contrast has now been probed through the same `sw5` window using the same capture path, but with recovered upload when the inline session stalled in the upload tail.

### Confirmed
- `addi x1, x0, 1`
  - falls into `main`
- `addi x1, x0, 4`
  - falls into `main`
- `addi x1, x0, 15`
  - falls into `main`
- `addi x1, x0, 22`
  - falls into `main`
- `addi x1, x0, 23`
  - falls into `main`
- `addi x1, x0, 32`
  - falls into `main`
- `addi x1, x0, 33`
  - falls into `main`
- `addi x1, x0, 63`
  - falls into `main`

### `x1_20` nuance
- `addi x1, x0, 20` does **not** reproduce as a stable dedicated family.
- First recovered run landed in a unique non-main class.
- The next two recovered runs fell back into `main`.
- So `x1_20` is currently best treated as unstable / not yet promotable to a trustworthy family.

### Hard interpretation
- The strongest stable anomalies observed so far are much more specific to the `rd=x0` encoding path than to the raw immediate field alone.
- In other words, many of the families that looked like “immediate-specific exceptions” on `addi x0, x0, imm` do **not** survive when only `rd` is changed to `x1`.
- That makes the current view much more consistent with a path that is sensitive to a semantic property of the instruction encoding, not just to a raw immediate bit pattern.

## `rs1=x1` Contrast While Keeping `rd=x0`

Minimal `addi x0, x1, imm` contrast has now been probed for the most important stable `x0,x0` anomalies.

### Confirmed
- `addi x0, x1, 20`
  - falls into `main`
- `addi x0, x1, 22`
  - falls into `main`
- `addi x0, x1, 63`
  - falls into `main`

### Hard interpretation
- The stable `x0,x0` anomalies are not just properties of the immediate field.
- They also do not survive a simple `rs1` change from `x0` to `x1`.
- Combined with the earlier `rd=x1` result, this pushes the current interpretation further:
  - the strongest anomalies are tied to the *full instruction semantic shape* around `rd=x0` and `rs1=x0`
  - not to a standalone immediate-bit island

### Current strongest pattern
- `addi x0, x0, imm` exposes several stable exception families.
- Replacing either:
  - `rd=x0 -> rd=x1`
  - or `rs1=x0 -> rs1=x1`
  usually collapses those exceptions back into `main`.
- So the present tunnel view is most consistent with a semantic sensitivity to the `addi x0, x0, imm` execution form itself.

## Revalidation Drift of the Classic `addi x0, x0, imm` Exceptions

Recent clean revalidation passes now show that the earlier “stable” exception islands are not all stable under the current capture chain:

- `addi x0, x0, 20`
  - original: `fam20_29`
  - revalidation: new drift family, not `main`, but also not the original `fam20_29`
- `addi x0, x0, 22`
  - original: `fam22`
  - revalidation: `main`
- `addi x0, x0, 23`
  - original: `fam23_28`
  - revalidation: `main`

### Updated interpretation
- The earlier exception-family map was useful to localize semantic sensitivity, but the current capture chain no longer supports treating all of those `addi x0, x0, imm` islands as stably reproducible.
- Right now:
  - `20` still shows “not-main” behavior, but its exact non-main family has drifted
  - `22` and `23` have collapsed back to `main`
- So the current best use of the `addi` map is as evidence of **semantic sensitivity existing at all**, not as a fully stable per-immediate lookup table.

## `xori x0, x0, imm` Contrast

To test whether the remaining `addi x0, x0, imm` sensitivity was really an `ADDI`-specific phenomenon or a generic I-type immediate effect, the same immediates were tried with:
- `xori x0, x0, imm`

Confirmed:
- `xori x0, x0, 20` -> `main`
- `xori x0, x0, 22` -> `main`
- `xori x0, x0, 23` -> `main`
- `xori x0, x0, 32` -> `main`

### Hard interpretation
- The currently visible anomaly is not a generic “immediate bit island” across I-type arithmetic instructions.
- It is much more specific to the `addi x0, x0, imm` execution form than to the raw immediate field alone.

## Revalidation of Classic `addi x0, x0, imm` Outliers

Clean revalidation on the current capture chain now shows:
- `addi x0, x0, 20`
  - original: `fam20_29`
  - revalidation: new non-main drift family
- `addi x0, x0, 22`
  - original: `fam22`
  - revalidation: `main`
- `addi x0, x0, 23`
  - original: `fam23_28`
  - revalidation: `main`

### Hard interpretation
- The old exception map is not fully replay-stable on the current capture chain.
- It still proves semantic sensitivity exists, but it is no longer safe to treat the old `20/22/23` families as fully stable reference anchors.

## `postexec` Contrast on `ebreak`

To test whether the older progbuf families were truly caused by executing the instruction body, `ebreak` was retried with:
- `postexec = 1`
- `postexec = 0`

Confirmed on the current chain:
- `ebreak_postexec1` -> `main`
- `ebreak_postexec0` -> `main`
- neither reproduces the earlier `ebreak-family`

### Hard interpretation
- On the current capture chain, the previously observed `ebreak-family` is not replay-stable.
- So the strongest durable evidence is no longer “specific progbuf instruction families”.
- The strongest durable evidence remains:
  - ordered `dmcontrol/haltreq/resumereq` control semantics
  - and the fact that instruction-form sensitivity exists at all
- Before treating any specific progbuf family as trustworthy again, the capture flow needs replay-stability checks with identical repeated stimuli.

## `haltreq + read 0x11` Replay Boundary

A fresh replay of the old `haltreq-family` reference was also attempted.

Current replay result:
- previously trusted `haltreq + read 0x11` replay did **not** reproduce the old family
- it also did **not** collapse cleanly back to `allzeros`
- instead it produced a new drift family on the current chain

### Hard interpretation
- Replay instability is no longer limited to progbuf instruction families.
- It is now also affecting previously stronger `haltreq`-driven control families.
- So the current main blocker has shifted again:
  - not “find more semantic samples”
  - but “make repeated captures of the *same* sample land in the *same* family”

## Replay Infrastructure Boundary

The most recent replay attempts showed that the instability is now tightly coupled to the capture infrastructure itself:
- repeated recovery can fail already at:
  - `open_hw_target`
  - `refresh_hw_device`
  - `upload_hw_ila_data`
  - or `write_hw_ila_data`
- concrete observed failures included:
  - `Invalid URL` while opening the hardware target
  - transient “out-of-date hw_server” errors
  - `Socket bind error` when local `hw_server` startup raced
  - `Unable to connect to debug core(s)` during recovery upload

### Hard interpretation
- At this point, the dominant blocker is no longer “which semantic sample to choose next”.
- It is the replay infrastructure itself:
  - `hw_server` lifecycle
  - stable `open_hw_target`
  - stable `refresh_hw_device`
  - stable `upload_hw_ila_data`/`write_hw_ila_data`
- So the next highest-value work is to collapse replay into a single deterministic, known-good hardware-manager session and prove that identical stimulus can be uploaded repeatedly without target/session drift.

## Same-Session Replay Result

The same-session replay infrastructure is now working end-to-end for both:
- `same_session_ebreak_replay_20260327_192219`
- `same_session_ebreak_replay_20260327_193537`
- `same_session_haltreq_a11_replay_20260327_192830`

Confirmed:
- `stimulus.log` is now valid and identical across `r1/r2/r3` within a given stimulus family.
- This means the XSDB replay script is finally issuing real JTAG sequences and the earlier `$seq`/escaping problems are gone.

For `ebreak`:
- `r1` lands in the old `main` family
- `r2` lands in a short `4-event` family:
  - `HASH=dca0fe94e18de54c9baadee9b9d6e1d43d4a76da909587dcff4dc4c3e06c07a6`
- `r3` lands in the short `3-event replay-phase` family:
  - `HASH=b8d5389691135086ded97d4bdebd9c64043996b28e53e19a0dd157219c0ec4f0`

A second fresh same-session `ebreak` replay confirmed that the split is not a one-off:
- `same_session_ebreak_replay_20260327_193537`
- `r1` again lands in `main`
- `r2` and `r3` now both land in the short `3-event replay-phase` family:
  - `HASH=b8d5389691135086ded97d4bdebd9c64043996b28e53e19a0dd157219c0ec4f0`
- `stimulus.log` remains valid and identical across all three repeats

For `haltreq + read 0x11`:
- `r1` lands in the old `main` family
- `r2` and `r3` both land in the same short `3-event replay-phase` family:
  - `HASH=b8d5389691135086ded97d4bdebd9c64043996b28e53e19a0dd157219c0ec4f0`

Window summaries:
- `r1`
  - `max_pos=0x21`
  - `max_neg=0x20`
  - full active shift window
- `r2/r3`
  - `max_pos=0x00`
  - `max_neg=0x00`
  - only the short replay-phase families

### Hard interpretation
- Same-session replay successfully removes most of the target-open / `hw_server` reconnect noise.
- But after that noise is removed, a new and more precise artifact is exposed:
  - replay index / session phase dominates family outcome more than stimulus semantics
- The strongest current evidence is:
  - `r1 = main`
  - later captures in the same session (`r2/r3`) collapse into short replay-phase families
  - that collapse now reproduces across two separate fresh `ebreak` same-session runs
- This happens across two different stimulus families (`ebreak`, `haltreq + read 0x11`), so the problem is not specific to one payload.
- Therefore the next highest-value question is not “which new semantic sample to try”, but:
  - how to reset or flush per-capture ILA/hw_ila_data state so that later captures in the same session do not deterministically degrade.

## Trigger Tightening: `posCounter == 0x08`

To test whether the replay collapse was just caused by triggering too early on broad background `SHIFT=1`, the same-session `ebreak` replay was rerun with the ILA trigger moved from:
- `u_ila_jtag__bscane2_SHIFT == 1`

to:
- `inst_jtag_tunnel/posCounter_reg == 8'h08`

Fresh run:
- `same_session_ebreak_replay_20260327_195447`

Confirmed:
- all three repeats (`r1/r2/r3`) now complete and write `csv/state/stimulus`
- the old short `3-event replay-phase` family disappears
- but the `r1` vs `r2/r3` split does **not** disappear

Classes:
- `r1` remains in the old `main` family:
  - `HASH=8f70dce344c6d7fb40bf11f5dd5ee0c636c51187d0d3d318a6747c640171a570`
- `r2` and `r3` now move together into a new short `2-event` family:
  - `HASH=b1c441606df8542beb09da94e1b66bc99f8e7dd3029550a5d8734aabc6efb310`

Window summaries:
- `r1`
  - `shift_window start=1994 end=2159 len=165`
  - `max_pos=0x21`
  - `max_neg=0x20`
- `r2/r3`
  - `shift_window start=0 end=4096 len=4096`
  - `max_pos=0x08`
  - `max_neg=0x07`

### Hard interpretation
- tightening the trigger to `posCounter == 0x08` is not enough to restore same-session stability
- but it **does** change the replay artifact shape:
  - from the old short `3/4-event replay-phase` family
  - to a new short `2-event / max_pos=0x08` family
- therefore the remaining instability is not just “trigger too broad on `SHIFT=1`”
- it is now more precisely a **per-replay phase / ILA state carry-over effect around the semantic window boundary**

The same tightened trigger was then applied to:
- `same_session_haltreq_a11_replay_20260327_200131`

Confirmed:
- `r1` again lands in a full semantic family:
  - `HASH=9764e3e4253b19fd011d8a38295b6e039f0a6f91956a4fb2547679ce1d5522be`
  - `EVENT_COUNT=577`
- `r2` and `r3` again move together into the same short `2-event / max_pos=0x08` family seen for `ebreak`:
  - `HASH=b1c441606df8542beb09da94e1b66bc99f8e7dd3029550a5d8734aabc6efb310`

Window summaries:
- `r1`
  - `shift_window start=1995 end=2160 len=165`
  - `max_pos=0x21`
  - `max_neg=0x20`
- `r2/r3`
  - `shift_window start=0 end=4096 len=4096`
  - `max_pos=0x08`
  - `max_neg=0x07`

Hard interpretation update:
- this is now a cross-family result, not an `ebreak`-specific artifact
- after tightening the trigger to the semantic boundary, `r1` remains stimulus-sensitive
- but later captures in the same hardware-manager session (`r2/r3`) still deterministically collapse into the same short `2-event / pos=0x08` family across at least:
  - `ebreak`
  - `haltreq + read 0x11`
- so the current blocker is no longer “early `SHIFT=1` background trigger”
- it is a deeper **same-session per-replay carry-over / phase-reset problem inside the ILA capture path**

### `close/open hw_target` Between Repeats Does Not Fix It

To test whether the carry-over lived only in the currently bound `hw_target` / `hw_ila` objects, the same-session `ebreak` replay was rerun with:
- `reopen_target=1`
- i.e. `close_hw_target` / `open_hw_target` / `refresh_hw_device` between every repeat

Fresh run:
- `same_session_ebreak_replay_20260327_200829`

Result:
- `r1` remains in `main`
  - `HASH=8f70dce344c6d7fb40bf11f5dd5ee0c636c51187d0d3d318a6747c640171a570`
- `r2/r3` still collapse into the same short `2-event / pos=0x08` family:
  - `HASH=b1c441606df8542beb09da94e1b66bc99f8e7dd3029550a5d8734aabc6efb310`

Hard interpretation:
- reopening the `hw_target` and rebinding the ILA is **not** sufficient to restore full semantic windows on `r2/r3`
- therefore the carry-over is deeper than the currently bound `hw_target` / `hw_ila` object

### `disconnect/connect hw_server` Between Repeats Also Does Not Fix It

The same-session `ebreak` replay was then rerun with a stronger reset step between repeats:
- `reconnect_server=1`
- i.e. `close_hw_target`, `disconnect_hw_server`, reconnect to `TCP:127.0.0.1:3121`, rediscover target, rebind ILA

Fresh run:
- `same_session_ebreak_replay_20260327_203345`

Result:
- `r1` still lands in a full semantic family:
  - `HASH=7ce3783f6758165a2b14f0229fe66623d70b8a701738b4e61f11d4ae2b10b642`
  - `EVENT_COUNT=597`
  - `max_pos=0x21`
  - `max_neg=0x21`
- `r2/r3` still collapse together, but now into yet another degraded family:
  - `HASH=7387b26dbc0f872e3a607a228f2d8a2b57d422ede5c373ab1ec52221b5ce7ca4`
  - `EVENT_COUNT=22`
  - `max_pos=0x0d`
  - `max_neg=0x0c`

Hard interpretation:
- reconnecting `hw_server` is not enough to restore replay stability
- but it changes the replay artifact again:
  - from `3/4-event`
  - to `2-event / pos=0x08`
  - to `22-event / pos=0x0d`
- so the remaining carry-over is deeper than:
  - the trigger itself
  - the currently bound `hw_target`
  - or a simple `hw_server` reconnect
- at this point the replay degradation is best understood as a broader live-session capture-state effect inside the Vivado hardware-manager/ILA stack

### Fully Independent Single-Run `ebreak` Sessions Are Stable

To test whether the collapse only appears when multiple repeats share a persistent Vivado/hardware-manager session, `ebreak` was rerun three times as completely independent one-shot sessions:
- `same_session_ebreak_replay_20260327_201654`
- `same_session_ebreak_replay_20260327_201857`
- `same_session_ebreak_replay_20260327_202059`

Each run used:
- `repeats=1`
- `posCounter == 0x08` trigger
- fresh Vivado invocation
- fresh `hw_server` restart from the wrapper

All three runs land in the same full semantic family:
- `HASH=8f70dce344c6d7fb40bf11f5dd5ee0c636c51187d0d3d318a6747c640171a570`
- `EVENT_COUNT=566`
- `max_pos=0x21`
- `max_neg=0x20`

Hard interpretation:
- the semantic path itself is still reproducible
- the collapse is specifically caused by **sharing a persistent same-session replay context**
- so the blocker is now more tightly localized to:
  - per-repeat carry-over inside the live Vivado/hardware-manager capture session
  - not the stimulus
  - not the design bitstream
  - not the trigger condition alone

### Independent One-Shot `haltreq + read 0x11` Is Not Yet Fully Stable

The same “fully independent one-shot session” experiment was then run for `haltreq + read 0x11`:
- `same_session_haltreq_a11_replay_20260327_202404`
- `same_session_haltreq_a11_replay_20260327_202601`
- `same_session_haltreq_a11_replay_20260327_202758`

All three runs used:
- `repeats=1`
- `posCounter == 0x08` trigger
- fresh Vivado invocation
- fresh `hw_server` restart from the wrapper

Results:
- run 1 lands in a new full family:
  - `HASH=15f4a4c1a727a10aeed60aa2c6e181b807ae7bb4b541c556454d22f8efed4d7e`
  - `EVENT_COUNT=604`
  - `max_pos=0x21`
  - `max_neg=0x21`
- runs 2 and 3 both land in the old `main` family:
  - `HASH=8f70dce344c6d7fb40bf11f5dd5ee0c636c51187d0d3d318a6747c640171a570`
  - `EVENT_COUNT=566`
  - `max_pos=0x21`
  - `max_neg=0x20`

Hard interpretation:
- unlike `ebreak`, `haltreq + read 0x11` is not yet fully stabilized even under completely independent one-shot sessions
- therefore:
  - same-session carry-over is definitely real
  - but it is not the only remaining source of instability
- the current evidence now splits the world into:
  - `ebreak`: stable under fresh one-shot sessions, unstable only under shared same-session replay
  - `haltreq + read 0x11`: still shows residual instability even under fresh one-shot sessions

### Fresh Vivado Alone Is Not Sufficient If `hw_server` Is Reused

To separate `Vivado session` state from `hw_server` state, `ebreak` was then rerun as:
- fresh one-shot Vivado invocation each time
- **without** restarting `hw_server` between runs
- still using the tightened `posCounter == 0x08` trigger

Runs:
- `same_session_ebreak_replay_20260327_204627`
- `same_session_ebreak_replay_20260327_204833`
- `same_session_ebreak_replay_20260327_205023`

Results:
- run 1 lands in the full `main` family:
  - `HASH=8f70dce344c6d7fb40bf11f5dd5ee0c636c51187d0d3d318a6747c640171a570`
  - `EVENT_COUNT=566`
  - `max_pos=0x21`
  - `max_neg=0x20`
- runs 2 and 3 both land in the degraded `22-event / pos≈0x0d` family:
  - `HASH=7387b26dbc0f872e3a607a228f2d8a2b57d422ede5c373ab1ec52221b5ce7ca4`
  - `EVENT_COUNT=22`
  - `max_pos=0x0d`
  - `max_neg=0x0c`

Hard interpretation:
- fresh Vivado is **not** enough by itself
- if the same `hw_server` is reused, later one-shot runs still degrade into the same `22-event / pos≈0x0d` family
- therefore the currently strongest localization is:
  - replay carry-over is at least partly anchored in the persistent `hw_server` / live hardware debug backend state
  - not only in the current Vivado Tcl session

### `disconnect/connect hw_server` Between Repeats Also Does Not Fix `haltreq + read 0x11`

The same stronger reset step used on `ebreak` was then applied to `haltreq + read 0x11`:
- `reconnect_server=1`
- i.e. `close_hw_target`, `disconnect_hw_server`, reconnect to `TCP:127.0.0.1:3121`, rediscover target, rebind ILA between repeats

Fresh run:
- `same_session_haltreq_a11_replay_20260327_203947`

Result:
- `r1` lands in a full semantic family:
  - `HASH=d6d2f38e45229769aa631fdd572048477ced275f37880102842029df526e5ee8`
  - `EVENT_COUNT=576`
  - `max_pos=0x21`
  - `max_neg=0x20`
- `r2/r3` again collapse together, but now into the same degraded family that `ebreak` reached under `reconnect_server=1`:
  - `HASH=7387b26dbc0f872e3a607a228f2d8a2b57d422ede5c373ab1ec52221b5ce7ca4`
  - `EVENT_COUNT=22`
  - `max_pos=0x0d`
  - `max_neg=0x0c`

Hard interpretation update:
- the `reconnect_server` artifact is now also cross-family:
  - `ebreak`
  - `haltreq + read 0x11`
- so reconnecting `hw_server` still does not recover replay stability
- it only pushes the replay degradation to a later boundary (`pos≈0x0d`) than the plain same-session case (`pos≈0x08`)

### `haltreq + read 0x11` With Explicit `preclear`

To test whether the residual `haltreq + read 0x11` instability is partly caused by leftover hart/debug state rather than only capture infrastructure, a preclear sequence was inserted before the normal `haltreq` sequence:
- `WRITE_RESUMEREQ`
- `NOP`
- `NOP`
- `WRITE_DMACTIVE`
- `NOP`
- `NOP`
- then the normal `WRITE_HALTREQ -> READ_0x11`

Fresh run:
- `same_session_haltreq_a11_replay_20260327_210530`

Confirmed:
- the generated `xsdb_replay.tcl` now really contains the preclear writes
- `stimulus.log` shows:
  - `WRITE_RESUMEREQ=...`
  - `WRITE_DMACTIVE=...`
  - then `WRITE_HALTREQ=...`
  - then `READ_0x11=...`
- the resulting capture does **not** collapse to the old `main` family
- instead it lands in a new full semantic family:
  - `HASH=3e457f58427f416a58c5b8535f38ee6572541a4f26965ac0add9b3666b97f163`
  - `EVENT_COUNT=584`
  - `max_pos=0x3f`
  - `max_neg=0x20`

Hard interpretation:
- `preclear` is not a no-op
- it changes the resulting full-window family in a strong and visible way
- this is the clearest current evidence that part of the `haltreq + read 0x11` drift is indeed tied to leftover hart/debug state, not only capture-session infrastructure

### `preclear` Stabilizes `haltreq + read 0x11` Under Shared `hw_server`

After verifying that the `preclear` path really executes (`WRITE_RESUMEREQ` and `WRITE_DMACTIVE` both appear in `stimulus.log`), the next test reused a single live `hw_server` but launched fresh one-shot Vivado sessions three times:
- `same_session_haltreq_a11_replay_20260327_210901`
- `same_session_haltreq_a11_replay_20260327_211103`
- `same_session_haltreq_a11_replay_20260327_211305`

All three used:
- `preclear=1`
- fresh one-shot Vivado invocation
- shared persistent `hw_server`
- tightened `posCounter == 0x08` trigger

All three runs land in the same full `main` family:
- `HASH=8f70dce344c6d7fb40bf11f5dd5ee0c636c51187d0d3d318a6747c640171a570`
- `EVENT_COUNT=566`
- `max_pos=0x21`
- `max_neg=0x20`

Hard interpretation:
- unlike the non-preclear shared-`hw_server` case, the `preclear` sequence removes the visible per-run drift for `haltreq + read 0x11`
- this is strong evidence that a major part of the `haltreq + read 0x11` instability was caused by leftover hart/debug state, not only `hw_server` reuse
- `ebreak` and `haltreq + read 0x11` are therefore now clearly split:
  - `ebreak` is dominated by replay/capture-session carry-over
  - `haltreq + read 0x11` can be largely normalized by explicit hart/debug-state preclear

### `preclear` Does Not Fix Same-Session Replay Collapse

Finally, the `preclear` sequence was applied inside a true same-session 3-repeat replay:
- `same_session_haltreq_a11_replay_20260327_211544`

Result:
- `r1` lands in a new full semantic family:
  - `HASH=34d358c3ad5227e1a1c18fc383ec77388e9c01979a15132e3e6abc2126f683eb`
  - `EVENT_COUNT=611`
- but `r2/r3` still collapse together into the same short `2-event / pos≈0x08` family:
  - `HASH=b1c441606df8542beb09da94e1b66bc99f8e7dd3029550a5d8734aabc6efb310`
  - `max_pos=0x08`
  - `max_neg=0x07`

Hard interpretation:
- `preclear` successfully normalizes leftover hart/debug state across fresh independent sessions
- but it does **not** remove the deeper same-session replay collapse
- therefore the remaining blocker is now cleanly split into two layers:
  1. hart/debug-state carry-over
     - mitigated by `preclear`
  2. same-session capture-session carry-over inside the live Vivado/hardware stack
     - **not** fixed by `preclear`
