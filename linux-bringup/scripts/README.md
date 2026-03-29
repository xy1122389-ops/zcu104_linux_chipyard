# Linux Bring-up Script Placeholders

This directory contains the stage-C Linux front-chain helpers.

Current scripts:
- `build_linux_chain_payload.sh`
- `download_linux_payload.sh`
- `start_linux_gdb.sh`
- `linux_chain_observe.gdb`

Current state:
- front-chain payload ELF is buildable
- address plan is printed and validated
- Linux-specific observation points exist for J-Link/GDB
- actual Linux image jump is still a placeholder

Stable default route remains unchanged:
- `bash /root/chipyard/fpga/scripts/run_ps_ddr_init.sh`
