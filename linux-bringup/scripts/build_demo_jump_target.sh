#!/usr/bin/env bash
set -euo pipefail

ROOT=/root/chipyard/fpga/linux-bringup/payload/demo-target
ELF="$ROOT/build/demo_target.elf"

echo "[info] Building demo jump target..."
make -C "$ROOT" clean all
echo "[info] Built: $ELF"
echo "[info] Key symbols:"
grep -E '(_prog_start| main$|demo_target_entry_marker|demo_target_loop_marker)' \
  "$ROOT/build/demo_target.nm" || true
