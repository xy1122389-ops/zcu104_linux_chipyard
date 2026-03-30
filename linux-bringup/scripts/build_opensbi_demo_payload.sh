#!/usr/bin/env bash
set -euo pipefail

OPENSBI=/root/chipyard/software/firemarshal/boards/default/firmware/opensbi
DEMO_BIN=/root/chipyard/fpga/linux-bringup/payload/demo-target/build/demo_target.bin
DTB_ADDR=0x82400000
FW_TEXT_START=0x80400000

if [[ ! -f "$DEMO_BIN" ]]; then
  echo "Error: demo target bin not found: $DEMO_BIN" >&2
  echo "Run: bash /root/chipyard/fpga/linux-bringup/scripts/build_demo_jump_target.sh" >&2
  exit 1
fi

echo "[info] Building OpenSBI FW_PAYLOAD at $FW_TEXT_START"
echo "[info] Embedded payload: $DEMO_BIN"
echo "[info] Embedded FDT addr: $DTB_ADDR"

make -C "$OPENSBI" clean >/dev/null 2>&1 || true
CROSS_COMPILE=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf- \
make -C "$OPENSBI" \
  PLATFORM=generic \
  FW_PAYLOAD=y \
  FW_TEXT_START="$FW_TEXT_START" \
  FW_PAYLOAD_PATH="$DEMO_BIN" \
  FW_PAYLOAD_FDT_ADDR="$DTB_ADDR" \
  -j2

echo "[info] Built OpenSBI payload:"
echo "  $OPENSBI/build/platform/generic/firmware/fw_payload.elf"
echo "  $OPENSBI/build/platform/generic/firmware/fw_payload.bin"
