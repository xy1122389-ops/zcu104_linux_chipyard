# A2 Night Sprint — Plan of Record

## Direction: A2 (Rocket → S_AXI_LPD → PS SDIO/J100)

## PROHIBITED (do not touch tonight)
- mmc_spi.c / spi-sifive / mmc-spi-slot
- PMOD / FMC / XDC SD SPI schemes
- MODE 0 / MODE 3 / CS inversion experiments
- Any PMOD MicroSD bitstream fix
- A1 (PS bootloader proxy) route
- Route B (PL SPI on PMOD0)

## Implementation Plan
1. Enable S_AXI_LPD (saxigp6) in PS blackbox
2. Add TL → AXI4 → saxigp6 bridge with address translation
3. Rocket 0x60000000-0x600FFFFF → PS 0xFF000000-0xFF0FFFFF
4. Phase 1: polling only (no interrupts)
5. DTS: sdhci@60170000, compatible="arasan,sdhci-8.9a"
6. Kernel: enable SDHCI + sdhci-of-arasan

## Bring-up Strategy
1. Phase 1: Polling, no clocks/interrupts in DTS
2. First test: GDB manual read of 0x60170000 (SDHCI version register)
3. Second test: Linux boot, check dmesg for sdhci-arasan probe
