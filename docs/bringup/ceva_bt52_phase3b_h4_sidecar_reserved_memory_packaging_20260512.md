# CEVA BT5.2 Phase 3B-H4 Sidecar Reserved Memory / Packaging Freeze

## 1. Goal

H4 freezes the current sidecar marker, image, stack, and packaging contract after the H3 marker-load proof. It does not modify payload, DTB/DTS, Linux driver, RTL, generated sources, or Vivado inputs.

## 2. Frozen Candidate Memory Contract

| Region | Start | End | Size | Owner | Purpose |
|---|---:|---:|---:|---|---|
| Legacy Phase 2.5 stage/P3BD area | `0x8F000000` | `0x8F0000D8` | existing | Linux/GDB legacy flow | Existing stage and breadcrumb evidence. |
| Sidecar marker page | `0x8F010000` | `0x8F010FFF` | 4 KiB | H3/H4 sidecar proof | Sidecar marker slots and future bridge markers. |
| Sidecar image window | `0x8F020000` | `0x8F02FFFF` | 64 KiB | sidecar loader / GDB dev proof | Sidecar text, rodata, data, bss, and stack. |

Current source anchors:

- `sidecar/ceva_bt52_sidecar/marker.h` freezes marker base `0x8F010000` and image base `0x8F020000`.
- `sidecar/ceva_bt52_sidecar/linker.ld` links the sidecar at `0x8F020000` with a 64 KiB window.
- `scripts/linux_boot_sidecar_marker_probe.gdb` restores the image to `0x8F020000` and dumps markers from `0x8F010000`.

## 3. Static Conflict Check

The static checker is:

```bash
scripts/check_ceva_sidecar_memory_contract.sh
```

It checks the sidecar marker and image windows against the current documented ranges:

| Existing region | Range |
|---|---:|
| OpenSBI FW_JUMP runtime | `0x80000000..0x80020DE8` |
| Linux Image | `0x80200000..0x830D4808` |
| Future payload / initramfs plan | `0x83000000..0x86FFFFFF` |
| DTB | `0x84000000..0x8401FFFF` |
| Front-chain payload | `0x88000000..0x883FFFFF` |
| Legacy stage/P3BD area | `0x8F000000..0x8F0000D8` |

H4 static result: `H4_MEMORY_CONTRACT=PASS`.

## 4. Packaging Contract

Current H4 packaging mode is development-only GDB restore:

```text
build sidecar.bin
clear marker page at 0x8F010000
restore sidecar.bin binary 0x8F020000
set pc = 0x8F020000
step or launch the sidecar execution context
dump marker page at 0x8F010000
```

This is not the final boot path. Future production packaging must choose one of:

- OpenSBI-managed sidecar load and launch.
- An earlier board bring-up loader that reserves and launches the sidecar before Linux HCI smoke.
- A vendor-provided firmware context if CEVA collateral provides an official controller runtime image and launch mechanism.

GDB restore remains a development proof path only.

## 5. What H4 Does Not Do

- Does not edit `linux-bringup/dtb/chipyard-zcu104-fedora.dtb`.
- Does not edit `linux-bringup/dtb/chipyard-zcu104-fedora.dts`.
- Does not edit `scripts/run_ps_ddr_init.tcl`.
- Does not rebuild payload.
- Does not run Vivado.
- Does not modify RTL.
- Does not add sidecar binary artifacts to git.
- Does not claim Linux baseline non-regression PASS beyond H3 marker proof.

## 6. PASS / PARTIAL / BLOCKED

PASS:

- Sidecar marker and image addresses are frozen in source.
- Static checker confirms no overlap with documented OpenSBI/Linux/DTB/front-chain/stage regions.
- GDB restore development packaging contract is documented.
- No protected/generated artifacts are committed.

PARTIAL:

- DTB reserved-memory carveout is not implemented in H4 because protected DTB/DTS edits are explicitly forbidden in this phase.
- Linux baseline non-regression remains deferred from H3 and should be handled by a future faster baseline check.

BLOCKED:

- None for the static H4 memory contract.

## 7. Next Safe Action

Proceed to H7 vendor runtime asset approval gate in parallel with H4 follow-up planning. Do not enter H5 ingress bridge until sidecar memory ownership is accepted for the intended run path and the baseline check strategy is clarified.
