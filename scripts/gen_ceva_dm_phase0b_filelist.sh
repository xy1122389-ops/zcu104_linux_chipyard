#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: $0 OUTPUT_FILE [CEVA_ROOT]" >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || usage

output_file=$1
requested_root=${2:-${CEVA_ROOT:-}}
script_dir=$(cd "$(dirname "$0")" && pwd)
override_file="$script_dir/ceva_phase0b_build_overrides.v"

choose_ceva_root() {
  local candidate
  for candidate in \
    "$requested_root" \
    "/mnt/e/桌面/CEVA_BT5.2/home/user007/project/CEVA_BT5.2" \
    "/home/user007/project/CEVA_BT5.2" \
    "/root/CEVA_BT5.2"
  do
    [[ -n "$candidate" ]] || continue
    if [[ -d "$candidate/rw-dm-hw-v11_00_03/HW" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "Unable to locate CEVA_ROOT. Set CEVA_ROOT or pass it as the second argument." >&2
  return 1
}

ceva_root=$(choose_ceva_root)
hw_root="$ceva_root/rw-dm-hw-v11_00_03/HW"
rtl_dir="$hw_root/IPs/Src/DM/rw_dm_top/verilog/rtl"
entry_list="$rtl_dir/rw_dm_top_rtl.list"
generator="$hw_root/bin/create_comp_file.pl"

[[ -f "$entry_list" ]] || { echo "Missing RTL entry list: $entry_list" >&2; exit 1; }
[[ -f "$generator" ]] || { echo "Missing CEVA filelist generator: $generator" >&2; exit 1; }
[[ -f "$override_file" ]] || { echo "Missing CEVA override file: $override_file" >&2; exit 1; }

mkdir -p "$(dirname "$output_file")"

tmp_file=$(mktemp)
ordered_file=$(mktemp)
cleanup() {
  rm -f "$tmp_file" "$ordered_file"
}
trap cleanup EXIT

pushd "$rtl_dir" >/dev/null
SOURCESLIB="$hw_root" "$generator" rw_dm_top rtl "$tmp_file" >/dev/null
popd >/dev/null

{
  printf '%s\n' "$override_file"
  cat "$tmp_file"
} > "$ordered_file"

[[ $(basename "$(sed -n '1p' "$ordered_file")") == "ceva_phase0b_build_overrides.v" ]] || {
  echo "Expected CEVA override file to be the first CEVA RTL file" >&2
  exit 1
}

[[ $(basename "$(sed -n '2p' "$ordered_file")") == "user_defines_dm.v" ]] || {
  echo "Expected user_defines_dm.v to be the first CEVA RTL file" >&2
  exit 1
}

[[ $(basename "$(sed -n '3p' "$ordered_file")") == "defines.v" ]] || {
  echo "Expected defines.v to be the third CEVA RTL file" >&2
  exit 1
}

grep -q '/rw_dm_reg/verilog/rtl/rw_dm_reg.v$' "$ordered_file" || {
  echo "Generated list is missing rw_dm_reg.v" >&2
  exit 1
}

grep -q '/rw_dm_top/verilog/rtl/rw_dm_top.v$' "$ordered_file" || {
  echo "Generated list is missing rw_dm_top.v" >&2
  exit 1
}

grep -q '/rw_dm_top/verilog/rtl/rw_dm_top_tglp_ext.v$' "$ordered_file" || {
  echo "Generated list is missing rw_dm_top_tglp_ext.v" >&2
  exit 1
}

mv "$ordered_file" "$output_file"
trap - EXIT

echo "Generated $(wc -l < "$output_file") CEVA RTL paths into $output_file" >&2
echo "Using CEVA_ROOT=$ceva_root" >&2