#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TS=$(date +%Y%m%d_%H%M%S)
LOG="$SCRIPT_DIR/../logs/runtime_alias_control_audit_${TS}.log"

{
  echo "==== zcu104 linux bringup bootrom config ===="
  sed -n '1,80p' /root/chipyard/fpga/src/main/scala/zcu104/LinuxBringupConfigs.scala

  echo
  echo "==== zcu104 default bootrom config ===="
  sed -n '1,80p' /root/chipyard/fpga/src/main/scala/zcu104/Configs.scala

  echo
  echo "==== generated address map excerpt ===="
  sed -n '70,130p' /root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig.chisel.log
  sed -n '160,190p' /root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig.chisel.log

  echo
  echo "==== bootaddr regmap ===="
  sed -n '1,120p' /root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig.0x1000.0.regmap.json

  echo
  echo "==== clint regmap head ===="
  sed -n '1,80p' /root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig.0x2000000.0.regmap.json

  echo
  echo "==== bootrom build commands ===="
  rg -n --fixed-strings -- "--change-addresses=-0x10000" /root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig.chisel.log

  echo
  echo "==== search explicit low-address peripherals in generated map ===="
  rg -n "reg = <0x0 |reg = <0x40|reg = <0x80|reg = <0x100|reg = <0x200|reg = <0x400|reg = <0x800|reg = <0x1000|reg = <0x2000>" \
    /root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig.chisel.log || true

  echo
  echo "==== search bootrom / bootaddr generated modules ===="
  find /root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/gen-collateral -maxdepth 1 -type f | rg 'TLROM|BootAddr|bootrom|TLInterconnectCoupler_cbus_to_bootrom|TLFragmenter_BootAddrReg'

  echo
  echo "==== prior low-window evidence summary ===="
  rg -n "FULL_MATCH_PLUS_2000_RUNS|PARTIAL_MATCH_PLUS_2000_BASES|NO_MATCH_PLUS_2000_BASES|FIRST_FULL_SELF_BASE|TRANSITION_INTERVAL|LIKELY_ALIAS_REMAP_WINDOW" \
    /root/chipyard/fpga/logs/runtime_payload_offset_evidence_20260322_144649.log

  echo
  echo "==== prior bootrom mismatch evidence summary ===="
  rg -n "BOOTROM_10000|BOOTROM_10020" \
    /root/chipyard/fpga/logs/runtime_bootrom_single_bit_probe_linux_20260322_135217.log \
    /root/chipyard/fpga/logs/runtime_bootrom_single_bit_probe_baremetal_20260322_135252.log
} > "$LOG"

echo "LOG:$LOG"
