#!/usr/bin/env bash
# start_linux_boot.sh — Run the full Linux bring-up sequence via GDB
#
# Prerequisites:
#   1. run_ps_ddr_init.sh completed (PS side DDR + bitstream)
#   2. xsdb_load_ddr.sh completed (fresh fw_payload + DTB in DDR)
#   3. J-Link GDB Server running (start_jlink_gdb_server.bat)
#   4. /tmp/opensbi_region.bin exists (dd if=fw_payload.bin bs=262144 count=1)
#   5. /tmp/cmdline_rodata_patch.bin exists
#
# After this script, kernel is running. Wait 60-120s then run:
#   ./scripts/dump_klog.sh
set -euo pipefail

GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
ELF=/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf
SCRIPT="$(dirname "$0")/linux_boot.gdb"

for f in "$GDB" "$ELF" "$SCRIPT"; do
  if [[ ! -f "$f" ]]; then
    echo "Error: not found: $f" >&2
    exit 1
  fi
done

for f in /tmp/opensbi_region.bin /tmp/cmdline_rodata_patch.bin; do
  if [[ ! -f "$f" ]]; then
    echo "Error: prerequisite not found: $f" >&2
    echo "  opensbi_region.bin: dd if=fw_payload.bin bs=262144 count=1 of=/tmp/opensbi_region.bin" >&2
    echo "  cmdline_rodata_patch.bin: see ADDRESS_PLAN.md" >&2
    exit 1
  fi
done

echo "[info] ELF:    $ELF"
echo "[info] Script: $SCRIPT"
echo "[info] GDB:    $GDB"
echo ""

exec "$GDB" -batch -x "$SCRIPT"
