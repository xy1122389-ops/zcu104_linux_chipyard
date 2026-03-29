# Demo Linux Front-Chain Assets

These are not real Linux boot artifacts.
They are small deterministic placeholder files used to verify that the
front-chain can really load files into the planned DDR addresses and report
their status over UART/GDB.

Generated files:
- `kernel-demo.bin`
- `payload-demo.bin`
- `dtb/demo-frontchain.dtb`

Generate them with:
- `bash /root/chipyard/fpga/linux-bringup/scripts/prepare_demo_assets.sh`
