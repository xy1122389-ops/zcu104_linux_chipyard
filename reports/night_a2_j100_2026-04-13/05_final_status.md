# Final Status & Next Steps — A2 Route (PS SDIO via S_AXI_LPD)

## STATUS: BUILD COMPLETE ✅

All software + hardware artifacts are ready for validation.

## Summary of Artifacts

| Artifact | Path | Size | Timestamp |
|----------|------|------|-----------|
| Bitstream | `generated-src/.../obj/ZCU104FPGATestHarness.bit` | 10.5MB | 2026-04-14 01:51 |
| Kernel Image | `linux-clean/arch/riscv/boot/Image` | 15.5MB | 2026-04-14 01:21 |
| DTB | `linux-bringup/dtb/chipyard-zcu104-linux-slip.dtb` | 4.6KB | 2026-04-14 01:21 |
| fw_payload.bin | `linux-bringup/payload/fw_payload.bin` | 17.6MB | 2026-04-14 01:24 |
| post_route.dcp | `generated-src/.../obj/post_route.dcp` | 83.3MB | 2026-04-14 01:50 |
| Vivado Log | `logs/vivado_a2_build_20260414_012642.log` | — | 2026-04-14 |

## Timing Results
- WNS = 6.928ns (positive → PASS, 7ns slack on 20ns period)
- WHS = 0.011ns (positive → PASS)
- All constraints met

## Next Steps for Validation
See [04_validation_plan.md](04_validation_plan.md) for details.

1. **Program FPGA** with new bitstream
2. **psu_init** (PS DDR + peripheral init)
3. **GDB smoke test**: read `0x601700FC` (SDHCI version register)
   - Non-zero → S_AXI_LPD path works
   - 0x00000000 → XPPU blocking
   - 0xFFFFFFFF → Address decode issue
4. **Linux boot** with new fw_payload.bin + DTB
5. **dmesg check**: look for `sdhci-arasan`, `mmc0`, `mmcblk0`

## Known Risks / Potential Blockers
1. **XPPU** may block PL→PS LPD access. Mitigation: check psu_init XPPU config, add `XPPU__APERTURE_*` settings.
2. **SDIO1 MIO pins** may not be enabled. The PS TCL only enables S_AXI_GP6; SDIO1 peripheral itself may need `PSU__SD1__PERIPHERAL__ENABLE {1}` and MIO pin assignment.
3. **SDIO1 clock** may not be running. Check CRL_APB SDIO1_REF_CTRL at 0xFF5E007C.
4. **Echo FIFO overflow** if >8 outstanding AXI transactions. Unlikely at 50MHz but worth monitoring.

## Git State
- Branch: `restore/from-ps-ddr-init-success`
- Modified files: zcu104ps.scala, XilinxZCU104PS.scala, Configs.scala, HarnessBinders.scala, chipyard-zcu104-linux-slip.dts, linux-clean/.config
- All changes are uncommitted (ready for review before commit)
