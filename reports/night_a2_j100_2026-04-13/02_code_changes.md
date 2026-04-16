# A2 Code Changes

## Modified Files

### 1. fpga-shells/.../zcu104ps/zcu104ps.scala
- **Added** `ZCU104PSLPDBundle` class — raw AXI4 slave-side IO (32-bit data, 6-bit ID, 49-bit addr)
- **Expanded** `ZCU104PSIOBundle` — added 37 saxigp6_* signals + saxi_lpd_aclk
- **Updated** Vivado TCL — added `PSU__USE__S_AXI_GP6 {1}` + `PSU__SAXIGP6__DATA_WIDTH {32}`

### 2. fpga-shells/.../xilinxzcu104ps/XilinxZCU104PS.scala
- **Updated** imports — added `chisel3.util._`, `ZCU104PSLPDBundle`
- **Added LPD IO to island** — `val lpd = IO(new ZCU104PSLPDBundle)` with full blackbox wiring (37 signals), LPD clock driven by island clock
- **Added LPD IO forwarding in wrapper** — `val lpd = IO(...)` forwarded via `lpd <> island.module.lpd`
- **Added** `ZCU104PSLPD` class — AXI4-to-PS-LPD bridge with:
  - AXI4SlaveNode matching chip's MMIO edge params (SimAXIMem pattern)
  - Address translation: +0x9F000000 (Rocket 0x60xxx → PS 0xFFxxx)
  - Echo field FIFOs (awEchoQ/arEchoQ) for TLToAXI4 compatibility
  - Flipped(ZCU104PSLPDBundle) output to connect to PS wrapper

### 3. src/.../zcu104/Configs.scala
- **Added** import: `ExtBus`, `MasterPortParams`
- **Added** `WithPSLPDMMIOPort` config: `ExtBus => Some(MasterPortParams(base=0x60000000, size=0x100000, beatBytes=4, idBits=4))`
- **Added** `WithPSLPDMem` and `WithPSLPDMMIOPort` to `WithZCU104Tweaks` config stack
- SPI/UART/GPIO/DDR configs left unchanged to minimize risk

### 4. src/.../zcu104/HarnessBinders.scala
- **Added** imports: `Parameters`, `AXI4EdgeParameters`, `LazyModule`, `ZCU104PSLPD`
- **Added** `WithPSLPDMem` HarnessBinder:
  - Handles `AXI4MMIOPort` from chip
  - Instantiates `ZCU104PSLPD` bridge (following SimAXIMem pattern)
  - Connects chip MMIO AXI4 → bridge → PS wrapper LPD IO

### 5. linux-bringup/dtb/chipyard-zcu104-linux-slip.dts
- **Added** `sdhci@60170000` node: `arasan,sdhci-8.9a`, bus-width=4, no-1-8-v, polling mode

### 6. Linux .config (linux-clean/.config)
- **Enabled**: CONFIG_MMC_SDHCI=y, CONFIG_MMC_SDHCI_PLTFM=y, CONFIG_MMC_SDHCI_OF_ARASAN=y, CONFIG_MMC_CQHCI=y

### 7. TestHarness.scala — NO CHANGES (MMIO handled via IOBinder/HarnessBinder automatically)

## Rebuild Requirements
- ALL Chisel changes require full re-elaboration + Vivado re-synthesis
- Linux .config requires kernel recompile
- DTS requires dtc recompile to DTB
- fw_payload.bin must be regenerated with new kernel + DTB
