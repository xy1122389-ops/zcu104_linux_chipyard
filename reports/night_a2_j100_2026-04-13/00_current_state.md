# A2 Night Sprint — Current State (2026-04-14)

## Git
- Branch: `restore/from-ps-ddr-init-success`
- HEAD: `b1fca88`
- Modified files: ZCU104NewShell.scala (PMOD pin remap — irrelevant to A2), linux_boot.gdb, shell.xdc

## Key Artifacts (BEFORE A2 changes)
| Artifact | Path | Timestamp |
|---|---|---|
| Bitstream | `generated-src/.../obj/ZCU104FPGATestHarness.bit` | Apr 13 23:16 |
| psu_init.tcl | `generated-src/.../obj/ip/zcu104ps/psu_init.tcl` | Apr 12 21:29 |
| fw_payload.bin | `linux-bringup/payload/fw_payload.bin` | Apr 10 01:16 |
| Linux Image | `linux-clean/.../boot/Image` | Apr 13 21:51 |
| vmlinux | `linux-clean/vmlinux` | Apr 13 21:51 |
| DTB (slip) | `linux-bringup/dtb/chipyard-zcu104-linux-slip.dtb` | Apr 13 00:51 |

## Confirmed Facts
1. J100 = PS-side SD Card Interface (SD1, MIO 46-51)
2. Current Rocket design has NO path to PS LPD peripherals
3. Only AXI port enabled: S_AXI_HP0_FPD (saxigp2) → DDR only
4. A2 is the only correct route: add S_AXI_LPD (saxigp6)
5. Address mapping: Rocket 0x60000000 → PS 0xFF000000 (LPD peripherals)
6. SDIO1 controller at PS physical address 0xFF170000
7. PS SD1 already enabled in PS TCL config (MIO 46..51, SD 2.0)
8. psu_init already configures SDIO1 clocks and resets
