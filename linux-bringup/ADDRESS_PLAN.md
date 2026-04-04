# ZCU104 Linux Front-Chain Address Plan

This address plan is for the stage-C Linux front-chain skeleton only.
It does not replace the current stable baremetal default flow.

## Stable default path

| Region | Start | End | Purpose |
|---|---:|---:|---|
| BootROM code | `0x00010000` | `0x00011fff` | current stable `_prog_start` / BootROM payload execution |
| Scratchpad | `0x08000000` | `0x0800ffff` | current stable `.bss` / stack for baremetal sdboot |
| DDR test touch range | `0x80000000` | `0x8000007f` | current stable DDR fixed + linear smoke test |

## Linux front-chain plan

| Region | Start | End | Purpose |
|---|---:|---:|---|
| Linux kernel image | `0x80200000` | `0x830d4808` | actual Linux `Image` placement (full 49MB embedded in fw_payload) |
| Linux first landing `_start` | `0x80200000` | `0x80200000` | physical Linux `_start` |
| Linux `_start_kernel` | `0x802010d0` | `0x802010d0` | early Linux handoff after image header |
| Linux `start_kernel` | `0x80800768` | `0x80800768` | physical `start_kernel` derived from `vmlinux` |
| DTB | `0x84000000` | `0x8401ffff` | DTB load region (moved past fw_payload end 0x830d4808) |
| Future payload blob / initramfs | `0x83000000` | `0x86ffffff` | planned extra payload region |
| Linux front-chain payload ELF | `0x88000000` | `0x883fffff` | standalone observable loader skeleton (`linux_chain.elf`) |
| Front-chain manifest | `0x883df000` | `0x883dffff` | manifest/status block written by Linux load script |
| Front-chain stack / reserve | `0x883e0000` | `0x883fffff` | stack and reserve inside front-chain payload region |
| OpenSBI FW_JUMP runtime load | `0x80000000` | `0x80020de8` | OpenSBI stage jumped to by front-chain |

## Linux image header facts

- `text_offset = 0x200000`
- `image_size = 0x2f32000`
- `flags = 0x0`
- `version = 0x2`
- `magic = "RISCV\\0\\0\\0"`
- `pe_offset = 0x4550`

## OpenSBI -> Linux entry note

- OpenSBI is built as `FW_JUMP`
- OpenSBI is loaded and executed at runtime from `0x80000000`
- OpenSBI uses the generic platform link-time base `0x80000000`
- This avoids relying on PIE relocation for internal override tables before
  platform initialization
- OpenSBI `FW_JUMP_ADDR = 0x80200000`
- OpenSBI `FW_PAYLOAD_FDT_ADDR = 0x84000000`
- Linux `Image` remains at its expected physical load base `0x80200000`
- `vmlinux` symbols are relocated for GDB by loading `vmlinux` with text base
  `0x80200000`

## Conflict check

- Stable baremetal scratchpad use stays in `0x08000000..0x0800ffff`
- Stable BootROM execute region stays in `0x00010000..0x00011fff`
- Stable DDR smoke test only touches the first `0x80` bytes at `0x80000000`
- Linux `Image` starts at `0x80200000`, well above the stable smoke-test bytes
- Linux image ends at `0x830d4808`, so DTB is placed at `0x84000000` to avoid overlap
- Front-chain has been moved to `0x88000000+`, so it no longer overlaps the Linux image
- OpenSBI at `0x80000000` remains below Linux `Image @ 0x80200000`, so the two regions do not overlap
- Linux manifest at `0x883df000` is below the reserved stack window
- Kernel / DTB / payload / front-chain / OpenSBI regions are non-overlapping in the current plan

## Current status

- Real file load to planned addresses is implemented
- Front-chain manifest is implemented
- Jump gating checks are implemented
- Actual jump is software-supported behind manifest flag
- OpenSBI `FW_JUMP` software route is prepared for Linux first-landing validation
- No verified Linux image handoff has been validated yet
- Current stable default path is still:
  - `bash /root/chipyard/fpga/scripts/run_ps_ddr_init.sh`
