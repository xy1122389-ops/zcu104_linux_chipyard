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
| Linux front-chain payload ELF | `0x80200000` | `0x803fffff` | standalone observable loader skeleton (`linux_chain.elf`) |
| Front-chain manifest | `0x803df000` | `0x803dffff` | manifest/status block written by Linux load script |
| Front-chain stack / reserve | `0x803e0000` | `0x803fffff` | stack and reserve inside front-chain payload region |
| Future kernel image | `0x80400000` | `0x823fffff` | planned Linux kernel load region |
| Future DTB | `0x82400000` | `0x8241ffff` | planned DTB load region |
| Future payload blob / initramfs | `0x83000000` | `0x86ffffff` | planned extra payload region |

## Conflict check

- Stable baremetal scratchpad use stays in `0x08000000..0x0800ffff`
- Stable BootROM execute region stays in `0x00010000..0x00011fff`
- Stable DDR smoke test only touches the first `0x80` bytes at `0x80000000`
- Linux front-chain regions start at `0x80200000`, so they do not overlap the current stable smoke test
- Linux manifest at `0x803df000` is below the reserved stack window
- Kernel / DTB / payload regions are non-overlapping in the current plan

## Current status

- Real file load to planned addresses is implemented
- Front-chain manifest is implemented
- Jump gating checks are implemented
- Actual jump is software-supported behind manifest flag
- No verified Linux image handoff has been validated yet
- Current stable default path is still:
  - `bash /root/chipyard/fpga/scripts/run_ps_ddr_init.sh`
