# CEVA BT5.2 Phase 3B-H3 Sidecar Marker Load Proof

## 1. Goal

H3 proves that the H1/H2 sidecar image can be loaded into the candidate sidecar memory window and can execute enough instructions to write the required marker slots.

This proof does not boot Linux from the sidecar path, does not modify payload, does not modify the Linux driver, does not modify RTL, does not run Vivado, and does not claim that CEVA vendor runtime is running.

## 2. Address Audit

Current documented regions from `linux-bringup/ADDRESS_PLAN.md`:

| Region | Range |
|---|---:|
| OpenSBI FW_JUMP runtime | `0x80000000..0x80020de8` |
| Linux image | `0x80200000..0x830d4808` |
| Future payload blob / initramfs plan | `0x83000000..0x86ffffff` |
| DTB | `0x84000000..0x8401ffff` |
| Front-chain payload | `0x88000000..0x883fffff` |
| Existing Phase 2.5 stage/P3BD marker area | `0x8F000000..0x8F0000D8` |

H3 sidecar candidate regions:

| Region | Range | Result |
|---|---:|---|
| Sidecar marker page | `0x8F010000..0x8F01008F` | Does not overlap documented Linux/OpenSBI/DTB/front-chain regions. |
| Sidecar image window | `0x8F020000..0x8F02FFFF` | Does not overlap documented Linux/OpenSBI/DTB/front-chain regions. |

Historical caution: an older Phase 1B diagnostic script used `0x8F010000` as a temporary EM dump buffer. H3 does not run that script. The H3 marker script explicitly clears and owns `0x8F010000..0x8F010090` for this proof.

## 3. Files Added

- `scripts/linux_boot_sidecar_marker_probe.gdb`

The script loads `sidecar.bin` at `0x8F020000`, clears the marker page at `0x8F010000`, steps the sidecar skeleton, dumps marker memory to `/tmp/phase3b_h3_sidecar_marker.bin`, and validates required marker values.

## 4. Commands Run

```bash
export PATH="/root/chipyard/.oclaw-env/bin:/root/chipyard/.oclaw-env/riscv-tools/bin:$PATH"
bash scripts/build_ceva_sidecar.sh
bash scripts/start_jlink_server.sh
timeout 180 riscv64-unknown-elf-gdb -q -batch -x scripts/linux_boot_sidecar_marker_probe.gdb
```

No Vivado, bitstream synthesis, payload rebuild, driver edit, RTL edit, or DTB/DTS edit was performed for this proof.

## 5. Marker Evidence

The H3 GDB probe returned `H3_GDB_RC=0` and printed `H3_MARKER_PROOF=PASS`.

Observed marker values:

| Marker | Offset | Observed value |
|---|---:|---:|
| `SIDECAR_BOOT_MAGIC` | `0x00` | `0x53434452424F4F54` |
| `SIDECAR_START` | `0x08` | `0x5349444553545254` |
| `SIDECAR_MAIN_ENTER` | `0x10` | `0x534344524D41494E` |
| `SIDECAR_INGRESS_READY` | `0x28` | `0x53494445494E4752` |
| `SIDECAR_LOOP_SEQ` | `0x68` | `0x0000000000000019` |
| `SIDECAR_LOOP_ALIVE` | `0x78` | `0x53434452414C4956` |

Raw dump excerpt:

```text
000000 53434452424f4f54 5349444553545254
000010 534344524d41494e 0000000000000000
000020 0000000000000000 53494445494e4752
000060 0000000000000000 0000000000000019
000070 0000000000000c03 53434452414c4956
```

## 6. Linux Baseline Attempt

A short Linux baseline check was attempted after the marker proof with:

```bash
env SKIP_DDR_INIT=1 JLINK_HOST=127.0.0.1 JLINK_PORT=3333 KERNEL_RUN_SECS=60 RUN_TAG=phase3b_h3_baseline_check bash ./run_phase2_ceva_bt_linux.sh
```

The run reached the existing Phase 2 launch flow and progressed through payload load and evidence-slot clearing, but it did not complete within the interactive execution window. The run was terminated under the recovery policy to avoid occupying J-Link with a long restore path.

Therefore H3 does not claim full Linux baseline non-regression PASS in this commit. It claims marker load and sidecar execution proof only.

## 7. PASS / PARTIAL / BLOCKED

PASS:

- Sidecar image build completed.
- J-Link connection reached the Rocket target.
- Sidecar image was restored to `0x8F020000`.
- Marker page was cleared and dumped.
- `SIDECAR_BOOT_MAGIC`, `SIDECAR_MAIN_ENTER`, `SIDECAR_LOOP_ALIVE`, and G9G-compatible sidecar markers were observed.

PARTIAL:

- Linux baseline non-regression remains deferred because the baseline run was stopped during the long existing payload restore/boot flow.

BLOCKED:

- None for marker load proof.

## 8. Next Safe Action

Proceed to H4 reserved memory and packaging freeze. H4 should turn the H3 address audit into a documented contract and should define how future Linux baseline checks avoid long restore ambiguity.
