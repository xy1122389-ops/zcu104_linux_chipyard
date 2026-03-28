#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <ir_hex> <dr_bits> <dr_hex> [jtag_hz]" >&2
  exit 2
fi

IR_HEX="$1"
DR_BITS="$2"
DR_HEX="$3"
JTAG_HZ="${4:-1000000}"

TMP_TCL=$(mktemp /tmp/xsdb_bscan_rawXXXX.tcl)
trap 'rm -f "$TMP_TCL"' EXIT

cat >"$TMP_TCL" <<EOF
connect -url tcp:127.0.0.1:3121
catch {jtag targets -set -filter {name == "xczu7"}} out
puts "SEL=\$out"
jtag frequency $JTAG_HZ
set seq [jtag sequence]
\$seq irshift -integer 12 $IR_HEX
\$seq drshift -capture -integer $DR_BITS $DR_HEX
puts "RUN=[\$seq run -hex]"
\$seq delete
exit
EOF

exec "$(dirname "$0")/run_xsdb_existing_server.sh" "$TMP_TCL"
