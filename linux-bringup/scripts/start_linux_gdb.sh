#!/usr/bin/env bash
set -euo pipefail

GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
ELF=/root/chipyard/fpga/linux-bringup/payload/linux-chain/build/linux_chain.elf
INIT=/root/chipyard/fpga/linux-bringup/scripts/linux_chain_observe.gdb

if [[ ! -x "$GDB" ]]; then
  echo "Error: GDB not found or not executable: $GDB" >&2
  exit 1
fi

if [[ ! -f "$ELF" ]]; then
  echo "Error: Linux front-chain ELF not found: $ELF" >&2
  echo "Run: /root/chipyard/fpga/linux-bringup/scripts/build_linux_chain_payload.sh" >&2
  exit 1
fi

if [[ ! -f "$INIT" ]]; then
  echo "Error: GDB helper not found: $INIT" >&2
  exit 1
fi

echo "[info] Linux front-chain ELF : $ELF"
echo "[info] GDB helper            : $INIT"
echo "[info] After GDB starts, run:"
echo "  source $INIT"
echo

exec "$GDB" "$ELF"
