# CEVA BT5.2 Sidecar Skeleton

This directory is the Phase 3B-H1 sidecar skeleton. It is only a baremetal execution proof scaffold.

It is not CEVA vendor runtime, not a Bluetooth controller, not an H4 stack, and not a Linux userspace fake controller. The first goal is to build a tiny image that can later prove an independent execution context by writing marker slots.

## Scope

- Builds a freestanding RV64 image with `_start`, stack setup, BSS clear, marker writes, and an idle loop.
- Uses the P4-C6 marker page: `0x8FBE0000`.
- Uses the P4-C6 sidecar image base: `0x8FBF0000`.
- Does not call `rwip_init()` or any vendor runtime function.
- Does not modify Linux driver, RTL, payload layout, DTB/DTS, OpenSBI, Vivado, or board scripts.

## Local Build

```bash
export PATH="/root/chipyard/.oclaw-env/bin:/root/chipyard/.oclaw-env/riscv-tools/bin:$PATH"
make -C sidecar/ceva_bt52_sidecar clean
make -C sidecar/ceva_bt52_sidecar
```
Build outputs stay under `sidecar/ceva_bt52_sidecar/build/` and are ignored by git.

## H1 PASS Criteria

- `sidecar.elf`, `sidecar.bin`, and `sidecar.map` build locally under `build/`.
- `git status --short` does not show generated sidecar outputs.
- Source review confirms marker constants match G9G offsets and H1 marker requirements.
- No driver, RTL, payload, DTB/DTS, Vivado, or board-side file is changed by this skeleton.

## H1 Markers

The skeleton publishes the required H1 marker constants:

- `SIDECAR_BOOT_MAGIC`
- `SIDECAR_MAIN_ENTER`
- `SIDECAR_LOOP_ALIVE`
- `SIDECAR_PANIC_CODE`

It also preserves the G9G-compatible slots for future capture:

- `SIDECAR_START`
- `SIDECAR_PRE_RWIP_INIT`
- `SIDECAR_INGRESS_READY`

## Future Run Proof

Future H3/H4 work must reserve memory, clear marker slots before launch, load this image, start a real sidecar execution context, and capture at least the boot, main-enter, loop-alive, and G9G-compatible sidecar-ready markers.

Until that run proof exists, this skeleton must not be described as a running vendor runtime or a real Bluetooth controller.