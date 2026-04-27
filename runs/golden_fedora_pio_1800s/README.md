# Golden Baseline: ZCU104 PL Rocket J100 Fedora PIO 1800s

**Frozen: 2026-04-25**  
**Status: LOCKED — DO NOT MODIFY**

## Run Identity

| Field | Value |
|-------|-------|
| RUN_TAG | fedora_pio_stable_20260425_132754 |
| Duration | 1800s |
| Boot mode | J-Link GDB + XSDB preload via SBA |
| SD slot | J100 (PS native microSD, MIO 46-51) |
| SDHCI mode | **PIO only** (no DMA, no ADMA2, no SDMA) |
| Kernel | Linux 6.6.0-fpga-min-g67bc4513761f-dirty #129 Thu Apr 23 18:56:45 CST 2026 |

## Acceptance Evidence

```raw
stage_mark = 0x5354474500000011   # ← systemd PID 1 reached, 17 stage flags set
[    0.000000] Linux version 6.6.0-fpga-min-g67bc4513761f-dirty
[    1.xxxxx] mmc0: SDHCI controller found [...]
[    2.xxxxx] mmcblk0: mmc0:...
[    3.xxxxx] EXT4-fs (mmcblk0p3): recovery complete
[   xx.xxxxx] systemd[1]: Detected architecture riscv64.
```

## Artifacts in This Directory

| File | Description |
|------|-------------|
| boot.log | Full GDB session log (12,897 bytes) |
| klog.bin | Raw kernel log_buf dump (131,072 bytes) |
| stage_mark.bin | 256-byte stage_mark region dump from PA 0x8F000000 |
| chipyard-zcu104-linux-slip.dtb | DTB used in this run (PIO caps-mask=0x10480000) |
| checksums.sha256 | SHA256 of fw_payload, linux_boot.gdb, dtb |

## Key Firmware Versions

| Artifact | SHA256 / Version |
|----------|-----------------|
| fw_payload.bin.v3patched | 759db54b9bebf2b77945b5b7e861517f564443d370bd1efe4625538f8de31480 |
| linux_boot.gdb | 83186b47b22659c23327c5904b4a5755ddf3c7cd9718de265c5354ed610425dc |
| chipyard-zcu104-linux-slip.dtb | bc516d3d99ad1aedc3bb5c751fe026ac344bd07f2371121403e94bdb082caa56 |
| OpenSBI | FW_PAYLOAD_FDT_ADDR=0x84000000, fw_payload.bin.v3patched |
| Kernel | #129 Apr 23, CONFIG_RISCV_ISA_ZICBOM=not set, CONFIG_SWIOTLB=y |

## Hardware Configuration (FIXED — NEVER CHANGE)

- Board: ZCU104
- Rocket reset vector: 0x10000 (BootROM)
- DDR (Rocket PA): 0x80000000
- SDHCI (Rocket PA): 0x60170000 → PS SDIO1 0xFF170000 via S_AXI_LPD
- DTB load address: 0x84000000
- stage_mark address: 0x8F000000
- J-Link JTAG: PMOD0 J55 (G6=TDI, H6=TMS, J6=TCK, J7=TDO), LVCMOS33

## Reproduction Command

```bash
KERNEL_RUN_SECS=1800 bash /root/chipyard/fpga/run_fedora_v3fix_pio.sh
```

## Verify Integrity

```bash
sha256sum -c /root/chipyard/fpga/runs/golden_fedora_pio_1800s/checksums.sha256
```
