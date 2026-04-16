# Build Status — A2 Route (PS SDIO via S_AXI_LPD)

## Phase 5A: Chisel Elaboration + Verilog ✅
- **Timestamp**: 2026-04-14 01:11
- **Generated Verilog**: `generated-src/.../gen-collateral/ZCU104FPGATestHarness.sv` (45,892 bytes)
- **PS TCL verified**: `PSU__USE__S_AXI_GP6 {1}`, `PSU__SAXIGP6__DATA_WIDTH {32}`
- **Auto-DTS verified**: `mmio-port-axi4@60000000` node present
- **37 saxigp6 signals confirmed** in `XilinxZCU104PSIsland.sv`

## Phase 5B: Kernel Build ✅
- **Timestamp**: 2026-04-14 01:21
- **Image**: `linux-clean/arch/riscv/boot/Image` (15,513,600 bytes)
- **CONFIG_MMC_SDHCI_OF_ARASAN=y** (built-in, not module)
- **sdhci_arasan symbols**: 36 confirmed in vmlinux

## Phase 5C: DTB + fw_payload.bin ✅
- **DTB**: `linux-bringup/dtb/chipyard-zcu104-linux-slip.dtb` (4,572 bytes, 2026-04-14 01:21)
  - Includes `sdhci@60170000` node (arasan,sdhci-8.9a, bus-width=4, polling mode)
- **fw_payload.bin**: `linux-bringup/payload/fw_payload.bin` (17,610,760 bytes, 2026-04-14 01:24)
  - OpenSBI PLATFORM=generic + new Linux Image
  - `_start` at 0x80000000, FDT at 0x84000000

## Phase 6: Vivado Synthesis + Implementation ✅
- **Started**: 2026-04-14 01:26
- **Completed**: 2026-04-14 01:52
- **Total time**: ~26 minutes (synth 9min + impl 17min)
- **Command**: `make SUB_PROJECT=zcu104 CONFIG=RocketZCU104LinuxBringupConfig bitstream`
- **Old PS IP cache deleted** (obj/ip/zcu104ps) to force S_AXI_GP6 regeneration
- **Log**: `logs/vivado_a2_build_20260414_012642.log`

### Results
- **Synthesis**: 0 errors, 0 critical warnings, 4423 warnings (all benign)
- **Timing** (post-route):
  - WNS = 6.928ns (setup PASS)
  - TNS = 0.000
  - WHS = 0.011ns (hold PASS)
  - THS = 0.000
  - **"All user specified timing constraints are met."**
- **Bitstream**: `obj/ZCU104FPGATestHarness.bit` (10,583,668 bytes)
- **Checkpoints**: post_synth.dcp, post_opt.dcp, post_place.dcp, post_route.dcp all generated
