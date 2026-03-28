#!/usr/bin/env bash
set -euo pipefail
cd /root/chipyard/fpga
scripts/run_xsdb_single_server.sh scripts/program_bit_only.tcl
