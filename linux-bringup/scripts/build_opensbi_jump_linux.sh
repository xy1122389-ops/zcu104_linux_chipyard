#!/usr/bin/env bash
set -euo pipefail

OPENSBI=/root/chipyard/software/firemarshal/boards/default/firmware/opensbi
FW_JUMP_ADDR=0x80200000
FW_JUMP_FDT_ADDR=0x82400000
CROSS=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-

if [[ ! -f /root/chipyard/software/firemarshal/boards/default/linux-clean/arch/riscv/boot/Image ]]; then
  echo "Error: Linux Image not found" >&2
  exit 1
fi

echo "[info] Building OpenSBI FW_JUMP for Linux Image handoff"
echo "[info] Runtime load addr   : 0x80000000"
echo "[info] Link-time base      : platform default (0x80000000)"
echo "[info] FW_JUMP_ADDR       : $FW_JUMP_ADDR"
echo "[info] FW_JUMP_FDT_ADDR   : $FW_JUMP_FDT_ADDR"

make -C "$OPENSBI" clean >/dev/null 2>&1 || true
CROSS_COMPILE="$CROSS" \
make -C "$OPENSBI" \
  PLATFORM=generic \
  CONFIG_SERIAL_SEMIHOSTING=n \
  FW_JUMP=y \
  FW_JUMP_ADDR="$FW_JUMP_ADDR" \
  FW_JUMP_FDT_ADDR="$FW_JUMP_FDT_ADDR" \
  -j2

echo "[info] Built OpenSBI jump firmware:"
echo "  $OPENSBI/build/platform/generic/firmware/fw_jump.elf"
echo "  $OPENSBI/build/platform/generic/firmware/fw_jump.bin"
