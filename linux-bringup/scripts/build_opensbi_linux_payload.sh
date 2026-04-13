#!/usr/bin/env bash
set -euo pipefail

OPENSBI=/root/chipyard/software/firemarshal/boards/default/firmware/opensbi
LINUX_IMAGE=/root/chipyard/software/firemarshal/boards/default/linux-clean/arch/riscv/boot/Image
FW_PAYLOAD_FDT_ADDR=0x84000000
CROSS=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-

if [[ ! -f "$LINUX_IMAGE" ]]; then
  echo "Error: Linux Image not found: $LINUX_IMAGE" >&2
  exit 1
fi

echo "[info] Building OpenSBI FW_PAYLOAD for Linux Image"
echo "[info] OpenSBI root       : $OPENSBI"
echo "[info] Linux Image       : $LINUX_IMAGE"
echo "[info] Runtime load addr : 0x80000000"
echo "[info] Link-time base    : platform default (0x80000000)"
echo "[info] FW_PAYLOAD_FDT_ADDR: $FW_PAYLOAD_FDT_ADDR"

make -C "$OPENSBI" clean >/dev/null 2>&1 || true
CROSS_COMPILE="$CROSS" \
make -C "$OPENSBI" \
  PLATFORM=generic \
  CONFIG_SERIAL_SEMIHOSTING=n \
  FW_PAYLOAD=y \
  FW_PAYLOAD_PATH="$LINUX_IMAGE" \
  FW_PAYLOAD_FDT_ADDR="$FW_PAYLOAD_FDT_ADDR" \
  -j2

FW_ELF="$OPENSBI/build/platform/generic/firmware/fw_payload.elf"
FW_BIN="$OPENSBI/build/platform/generic/firmware/fw_payload.bin"

echo "[info] Built OpenSBI Linux payload:"
echo "  $FW_ELF"
echo "  $FW_BIN"
echo "[info] Key symbols:"
/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-nm -n "$FW_ELF" | \
  grep -E '(_start$|fw_boot_hart|fw_next_arg1|fw_next_addr|fw_next_mode|sbi_init$)' || true
