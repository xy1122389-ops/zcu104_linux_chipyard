#!/usr/bin/env bash
set -euo pipefail

GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
ELF=/root/chipyard/fpga/src/main/resources/zcu104/sdboot/build/sdboot.elf
INIT=/root/chipyard/fpga/scripts/rocket_debug_init.gdb

if [[ ! -x "$GDB" ]]; then
  echo "Error: GDB not found or not executable: $GDB" >&2
  exit 1
fi

if [[ ! -f "$ELF" ]]; then
  echo "Error: ELF not found: $ELF" >&2
  exit 1
fi

if [[ ! -f "$INIT" ]]; then
  echo "Error: GDB init script not found: $INIT" >&2
  exit 1
fi

echo "[info] ELF : $ELF"
echo "[info] GDB : $GDB"
echo "[info] After GDB starts, run:"
echo "  source $INIT"
echo

exec "$GDB" "$ELF"
