#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARKER_H="${ROOT_DIR}/sidecar/ceva_bt52_sidecar/marker.h"
LINKER_LD="${ROOT_DIR}/sidecar/ceva_bt52_sidecar/linker.ld"
CONTRACT="${ROOT_DIR}/scripts/ceva_reserved_memory_contract.sh"

source "$CONTRACT"

require_text() {
  local needle="$1"
  local file="$2"

  if ! grep -Fq "$needle" "$file"; then
    echo "FAIL: missing '$needle' in $file" >&2
    exit 1
  fi
}

hex() {
  printf '%d' "$((16#${1#0x}))"
}

overlaps() {
  local start_a end_a start_b end_b
  start_a=$(hex "$1")
  end_a=$(hex "$2")
  start_b=$(hex "$3")
  end_b=$(hex "$4")

  (( start_a <= end_b && start_b <= end_a ))
}

check_no_overlap() {
  local name_a="$1" start_a="$2" end_a="$3" name_b="$4" start_b="$5" end_b="$6"

  if overlaps "$start_a" "$end_a" "$start_b" "$end_b"; then
    echo "FAIL: $name_a $start_a..$end_a overlaps $name_b $start_b..$end_b" >&2
    exit 1
  fi

  echo "PASS: $name_a does not overlap $name_b"
}

require_text "CEVA_BT52_SIDECAR_MARKER_BASE 0x000000008FBE0000ULL" "$MARKER_H"
require_text "CEVA_BT52_SIDECAR_IMAGE_BASE 0x000000008FBF0000ULL" "$MARKER_H"
require_text "ORIGIN = 0x000000008FBF0000" "$LINKER_LD"
require_text "LENGTH = 64K" "$LINKER_LD"

SIDECAR_MARKER_START="$CEVA_SIDECAR_MARKER_START"
SIDECAR_MARKER_END="$CEVA_SIDECAR_MARKER_END"
SIDECAR_IMAGE_START="$CEVA_SIDECAR_IMAGE_START"
SIDECAR_IMAGE_END="$CEVA_SIDECAR_IMAGE_END"

echo "CEVA sidecar memory contract static check"
echo "marker=${SIDECAR_MARKER_START}..${SIDECAR_MARKER_END}"
echo "image=${SIDECAR_IMAGE_START}..${SIDECAR_IMAGE_END}"

for region in "${CEVA_MEMORY_REGIONS[@]}"; do
  IFS=: read -r name start end <<<"$region"
  check_no_overlap SidecarMarker "$SIDECAR_MARKER_START" "$SIDECAR_MARKER_END" "$name" "$start" "$end"
  check_no_overlap SidecarImage "$SIDECAR_IMAGE_START" "$SIDECAR_IMAGE_END" "$name" "$start" "$end"
done

check_no_overlap SidecarMarker "$SIDECAR_MARKER_START" "$SIDECAR_MARKER_END" SidecarImage "$SIDECAR_IMAGE_START" "$SIDECAR_IMAGE_END"

echo "H4_MEMORY_CONTRACT=PASS"
