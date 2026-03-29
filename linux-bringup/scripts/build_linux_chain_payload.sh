#!/usr/bin/env bash
set -euo pipefail

ROOT=/root/chipyard/fpga/linux-bringup/payload/linux-chain
ELF="$ROOT/build/linux_chain.elf"

echo "[info] Building Linux front-chain payload..."
make -C "$ROOT" clean all
echo "[info] Built: $ELF"
echo "[info] Key symbols:"
grep -E '(_prog_start| main$|linux_chain_start_marker|linux_payload_stage_marker|linux_kernel_stage_marker|linux_dtb_stage_marker|linux_jump_stage_marker|linux_count_loop_marker)' \
  "$ROOT/build/linux_chain.nm" || true
echo "[info] Additional load-done markers:"
grep -E '(payload_load_done_marker|kernel_load_done_marker|dtb_load_done_marker|linux_ready_to_jump_marker|linux_jump_taken_marker)' \
  "$ROOT/build/linux_chain.nm" || true
