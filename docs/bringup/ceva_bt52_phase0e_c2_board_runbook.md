# CEVA BT5.2 Phase 0E-C2 - Board Runbook

## One-line goal

Use the future Phase 0E bitstream and the C1 baremetal sdboot payload to validate that `dm_sw_irq` reaches Rocket through PLIC.

## Do not run this on old bitstreams

Old Phase 0B, 0C, and 0D bitstreams do not contain:

```text
dm_sw_irq -> wrapper -> IntSourceNode -> ibus.fromSync -> PLIC
```

If you run the probe reader on one of those older bitstreams, an IRQ failure or timeout does not prove the C1 software is wrong.

## Preconditions

All of the following must already be true before treating any C2 result as valid:

1. A new Phase 0E bitstream has already been built outside this runbook.
2. That Phase 0E bitstream has already been loaded onto the board.
3. The loaded Phase 0E bitstream is the one that contains the `dm_sw_irq -> PLIC` wiring.
4. The matching C1 `sdboot.bin` and `sdboot.elf` artifacts exist locally.
5. The board has completed the normal PS DDR and PS-PL initialization flow.
6. The C1 sdboot image has already been given time to run after the new bitstream was loaded.
7. J-Link GDB Server uses `127.0.0.1:3333`.

This runbook does not build bitstreams, does not run synthesis, and does not modify RTL or software sources.

## Canonical artifacts

Use the compile-passed C1 artifacts from:

- `src/main/resources/zcu104/sdboot/build/sdboot.elf`
- `src/main/resources/zcu104/sdboot/build/sdboot.bin`

Use the existing probe reader:

- `scripts/ceva_phase0e_c15_baremetal_probe_read.sh`

## Step 0: Set Paths And Capture Baseline

Run this first and keep the terminal output with the board log:

```sh
cd /root/chipyard/fpga

pwd
git branch --show-current
git status --short
git log --oneline -5

export PHASE0E_BIT=/absolute/path/to/your/Phase0E.bit
export PHASE0E_PSU_INIT_TCL=/absolute/path/to/your/psu_init.tcl
export C1_ELF=/root/chipyard/fpga/src/main/resources/zcu104/sdboot/build/sdboot.elf
export C1_BIN=/root/chipyard/fpga/src/main/resources/zcu104/sdboot/build/sdboot.bin

test -f "$PHASE0E_BIT"
test -f "$PHASE0E_PSU_INIT_TCL"
test -f "$C1_ELF"
test -f "$C1_BIN"

ls -lh "$PHASE0E_BIT" "$PHASE0E_PSU_INIT_TCL" "$C1_ELF" "$C1_BIN"
sha256sum "$PHASE0E_BIT" "$C1_ELF" "$C1_BIN"
```

If any file is missing, stop here.

## Step 1: Confirm The ELF Is Really The C1 Probe Build

The probe reader depends on symbol names from the matching C1 ELF. Confirm them before touching the board:

```sh
cd /root/chipyard/fpga

/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-nm "$C1_ELF" | \
  grep -E 'phase0e_irq_trap_entry|phase0e_irq_trap_handler|phase0e_irq_probe_magic|phase0e_irq_probe_mcause|phase0e_irq_probe_claim_id|phase0e_irq_probe_handler_count|phase0e_irq_probe_done'
```

If these symbols are not present, stop. The probe reader is not targeting the same C1 image.

## Step 2: Start Or Reconfirm J-Link GDB Server

The only supported path for this stage is `127.0.0.1:3333`.

```sh
cd /root/chipyard/fpga

bash scripts/start_jlink_server.sh
nc -z -w 3 127.0.0.1 3333 && echo JLINK_OK
```

If `JLINK_OK` does not print, stop here.

## Step 3: Load The New Phase 0E Bitstream

Do not use an old Phase 0B, 0C, or 0D bitstream here.

If you are using the repo-local Tcl helper for reprogramming an already-built bitstream, export the bitstream paths and run it through your normal Vivado hardware-manager flow:

```sh
cd /root/chipyard/fpga

export CHIPYARD_BITSTREAM_LINUX="$PHASE0E_BIT"
export CHIPYARD_PSU_INIT_TCL_LINUX="$PHASE0E_PSU_INIT_TCL"

echo "In a Vivado hardware Tcl session, run:"
echo "source /root/chipyard/fpga/scripts/reprogram_fpga_only.tcl"
```

If you use another approved hardware programming flow, that is fine, but the loaded bitstream must be the new Phase 0E image and not an older board image.

After programming the board, give the core a short window to start running the embedded C1 image before probing.

## Step 4: Reconfirm CEVA VERSION Before IRQ Conclusions

This is the first branch point. If VERSION is wrong, stop before reading probes.

```sh
cd /root/chipyard/fpga

LOG_VERSION=/tmp/phase0e_c2_version_$(date +%Y%m%d_%H%M%S).log
bash scripts/read_ceva_version.sh | tee "$LOG_VERSION"
```

Expected stable values remain:

- `0x65000004 = 0x0B000500`
- `0x65000404 = 0x0B000600`
- `0x65000804 = 0x0B001100`

If VERSION does not read correctly, do not continue to IRQ conclusions.

## Step 5: Confirm The Board Is Running The Matching C1 Image

The probe reader only makes sense if the loaded board image and the local ELF agree.

Use this checklist before the actual probe read:

```sh
cd /root/chipyard/fpga

echo "BIT  : $PHASE0E_BIT"
echo "ELF  : $C1_ELF"
echo "BIN  : $C1_BIN"
sha256sum "$C1_ELF" "$C1_BIN"
echo "Probe reader: scripts/ceva_phase0e_c15_baremetal_probe_read.sh"
echo "Wait at least a few seconds after programming so the C1 flow can arm PLIC, trigger CEVA, and populate probes."
```

If the new Phase 0E bitstream was not produced from the matching C1 `sdboot.bin`, stop here and rebuild outside this runbook.

## Step 6: Run The Probe Reader

This is the actual C2 board-facing readback step.

```sh
cd /root/chipyard/fpga

LOG_PROBE=/tmp/phase0e_c2_probe_$(date +%Y%m%d_%H%M%S).log
ELF="$C1_ELF" bash scripts/ceva_phase0e_c15_baremetal_probe_read.sh | tee "$LOG_PROBE"
```

Useful follow-up summary commands:

```sh
grep -E 'PASS:|FAIL:|OBSERVE:|PROBE_|LIVE_' "$LOG_PROBE"
grep -E 'PROBE_MAGIC|PROBE_MCAUSE|PROBE_CLAIM_ID|PROBE_HANDLER_COUNT|PROBE_DONE|PROBE_CEVA_STATUS_BEFORE_ACK|PROBE_CEVA_STATUS_AFTER_ACK' "$LOG_PROBE"
```

## Hard PASS Fields

For the first real board pass, treat only these seven probe facts as hard PASS or FAIL:

1. `PROBE_MAGIC` is the expected C1 magic.
2. `PROBE_HANDLER_COUNT` is non-zero.
3. `PROBE_MCAUSE` is machine external interrupt.
4. `PROBE_CLAIM_ID` equals the CEVA PLIC source id.
5. `PROBE_CEVA_STATUS_BEFORE_ACK` shows `INTSTAT1[3] = 1`.
6. `PROBE_CEVA_STATUS_AFTER_ACK` shows `INTSTAT1[3] = 0`.
7. `PROBE_DONE` is set.

The current script already enforces this policy.

## Observation-Only Fields

These should be printed and reviewed, but not used as first-pass hard failure conditions:

- `PROBE_PLIC_PENDING_BEFORE_CLAIM`
- `PROBE_PLIC_PENDING_AFTER_ACK`
- `PROBE_COMPLETION_WRITTEN`
- `PROBE_TIMEOUT`
- `LIVE_PLIC_PENDING`

Reason: pending visibility depends on where the halt point lands relative to claim and complete. For the first board pass, claim id and CEVA status clear are stronger evidence than any single pending snapshot.

## FAIL Routing

Use the following split before widening scope.

### 1. VERSION read fails

Symptoms:

- `bash scripts/read_ceva_version.sh` fails
- `0x65000004` is unreadable, zero, `0xFFFFFFFF`, or wrong-version data

Meaning:

- do not draw any IRQ conclusion yet
- suspect wrong bitstream loaded, CEVA path not live, reset or init problem, or J-Link access problem

Action:

- stop C2
- fix basic CEVA visibility first

### 2. `PROBE_HANDLER_COUNT = 0`

Meaning:

- the trap handler did not run

Most likely branches:

- old non-Phase 0E bitstream is still loaded
- the board is not actually running the matching C1 sdboot image
- the run window was too short and probes were sampled too early
- the IRQ path did not reach Rocket

Action:

- first reconfirm the loaded bitstream is the new Phase 0E image
- then reconfirm the C1 image matches the local `sdboot.elf` and had time to run

### 3. `PROBE_MCAUSE` is not machine external interrupt

Meaning:

- the trap fired, but not for the expected machine external cause

Action:

- stop treating this as a clean IRQ PASS
- inspect whether another trap source fired or whether the trap entry was sampled in the wrong state

### 4. `PROBE_CLAIM_ID` is wrong

Meaning:

- PLIC claimed the wrong source, or no valid CEVA source was claimed

Action:

- treat this as a source-id or wiring mismatch until proven otherwise
- do not use pending snapshots alone to override this result

### 5. CEVA status does not clear across ack

Symptoms:

- `PROBE_CEVA_STATUS_BEFORE_ACK` does not show bit 3 set
- or `PROBE_CEVA_STATUS_AFTER_ACK` still shows bit 3 set

Meaning:

- the CEVA local IRQ status did not match the expected trigger-then-clear sequence

Action:

- treat this as the strongest sign that the local CEVA ack path did not complete as expected
- debug CEVA status and ack behavior before arguing about pending timing

## Exit Criteria For A First Board PASS

Treat the first board pass as successful when all of the following are true in one run:

1. The new Phase 0E bitstream was the one loaded on board.
2. `bash scripts/read_ceva_version.sh` passes.
3. The matching C1 `sdboot.elf` was used by the probe reader.
4. The probe reader returns a hard PASS.
5. Observation-only fields do not contradict the main story badly enough to suspect a mismatched halt point.

## Not Part Of This Runbook

This runbook does not cover:

- building the new Phase 0E bitstream
- synthesizing or implementing hardware
- modifying RTL or Scala generator code
- changing `head.S` or `baremetal.c`
- changing Device Tree, Linux drivers, or BlueZ
- committing results