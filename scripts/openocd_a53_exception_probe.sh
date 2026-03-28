#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LOG_DIR="$SCRIPT_DIR/../logs"
mkdir -p "$LOG_DIR"

TS=${TS:-$(date +%Y%m%d_%H%M%S)}
LOG="$LOG_DIR/openocd_a53_exception_probe_${TS}.log"
HOST=${OPENOCD_HOST:-$(ip route | awk '/default/ {print $3; exit}')}
PORT=${OPENOCD_TELNET_PORT:-4444}

telnet_seq() {
  {
    for item in "$@"; do
      if [[ "$item" == SLEEP:* ]]; then
        sleep "${item#SLEEP:}"
      else
        printf '%s\n' "$item"
      fi
    done
  } | nc -w 6 "$HOST" "$PORT" | perl -pe 's/\0//g'
}

{
  echo "OPENOCD_HOST=$HOST"
  echo "OPENOCD_TELNET_PORT=$PORT"
  echo "==== PHASE 1: reset bits and EDPRSR before release ===="
  telnet_seq \
    "targets" \
    "SLEEP:1" \
    "uscale.axi read_memory 0xfd1a0104 32 1" \
    "SLEEP:1" \
    "uscale.dap apreg 1 4 0x80410314" \
    "SLEEP:1" \
    "uscale.dap apreg 1 0xc" \
    "SLEEP:1" \
    "exit"

  echo "==== PHASE 2: release_apu and power-domain transition ===="
  telnet_seq \
    "targets uscale.a53.0" \
    "SLEEP:1" \
    "uscale.a53.0 aarch64 smp off" \
    "SLEEP:1" \
    "uscale.axi write_memory 0xfd1a0104 32 {0x3d0f}" \
    "SLEEP:2" \
    "release_apu 0" \
    "SLEEP:2" \
    "targets" \
    "SLEEP:1" \
    "uscale.axi read_memory 0xfd1a0104 32 1" \
    "SLEEP:1" \
    "uscale.dap apreg 1 4 0x80410314" \
    "SLEEP:1" \
    "uscale.dap apreg 1 0xc" \
    "SLEEP:1" \
    "exit"

  echo "==== PHASE 3: pending debug-request + release_apu halt at reset vector ===="
  telnet_seq \
    "targets uscale.a53.0" \
    "SLEEP:1" \
    "uscale.a53.0 aarch64 smp off" \
    "SLEEP:1" \
    "uscale.a53.0 arp_halt" \
    "SLEEP:1" \
    "uscale.axi write_memory 0xfd1a0104 32 {0x3d0f}" \
    "SLEEP:2" \
    "release_apu 0" \
    "SLEEP:2" \
    "targets" \
    "SLEEP:1" \
    "uscale.a53.0 curstate" \
    "SLEEP:1" \
    "uscale.a53.0 debug_reason" \
    "SLEEP:1" \
    "uscale.a53.0 get_reg {pc cpsr ELR_EL3 ESR_EL3 SPSR_EL3}" \
    "SLEEP:1" \
    "uscale.a53.0 mdw 0xffff0000 8" \
    "SLEEP:1" \
    "exit"

  echo "==== PHASE 4: exception catch on first stepped instruction ===="
  telnet_seq \
    "targets uscale.a53.0" \
    "SLEEP:1" \
    "uscale.a53.0 aarch64 smp off" \
    "SLEEP:1" \
    "uscale.a53.0 arp_halt" \
    "SLEEP:1" \
    "uscale.axi write_memory 0xfd1a0104 32 {0x3d0f}" \
    "SLEEP:2" \
    "release_apu 0" \
    "SLEEP:2" \
    "uscale.a53.0 catch_exc sec_el3" \
    "SLEEP:1" \
    "step" \
    "SLEEP:3" \
    "targets" \
    "SLEEP:1" \
    "uscale.a53.0 curstate" \
    "SLEEP:1" \
    "uscale.a53.0 debug_reason" \
    "SLEEP:1" \
    "uscale.a53.0 get_reg {pc cpsr ELR_EL3 ESR_EL3 SPSR_EL3}" \
    "SLEEP:1" \
    "uscale.a53.0 catch_exc off" \
    "SLEEP:1" \
    "exit"
} | tee "$LOG"

echo "LOG=$LOG"
