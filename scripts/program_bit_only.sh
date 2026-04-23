#!/usr/bin/env bash
set -euo pipefail

powershell.exe -Command 'cd C:\Users\Public; E:\PRO_APP\xilinx\Vivado\2021.2\bin\xsdb.bat C:\Users\Public\xsdb_program_bit_only.tcl 2>&1'