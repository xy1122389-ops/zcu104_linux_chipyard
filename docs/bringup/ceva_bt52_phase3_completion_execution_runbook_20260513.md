{
  "cells": [
    {
      "cell_type": "markdown",
      "metadata": {
        "language": "markdown"
      },
      "source": [
        "# CEVA BT5.2 Phase3 Completion Execution Runbook",
        "",
        "This runbook is the execution layer for the Phase3 completion gate. It keeps Phase4 locked until the real vendor-runtime path is proven end to end.",
        "",
        "Current expected state before real vendor approval and runtime integration is `PHASE3_COMPLETION_GATE=INCOMPLETE`."
      ]
    },
    {
      "cell_type": "markdown",
      "metadata": {
        "language": "markdown"
      },
      "source": [
        "## 1. Always Start Here",
        "",
        "```bash",
        "cd /root/chipyard/fpga",
        "bash scripts/collect_ceva_phase3_status_snapshot.sh",
        "bash scripts/check_ceva_phase3_completion_gate.sh --status",
        "```",
        "",
        "If `--require-pass` fails, do not start Phase4. Continue closing the missing Phase3 evidence items instead."
      ]
    },
    {
      "cell_type": "markdown",
      "metadata": {
        "language": "markdown"
      },
      "source": [
        "## 2. Execution Order",
        "",
        "| Order | Work | Output | Hard rule |",
        "|---:|---|---|---|",
        "| 1 | Close vendor approval | `00_vendor_approval_closed.md` | Do not copy/link vendor code before this. |",
        "| 2 | Build approved runtime externally or in approved local path | `01_vendor_runtime_link_pass.md` | Do not commit restricted vendor assets. |",
        "| 3 | Integrate init markers | `02_rwip_init_and_driver_init_pass.md` | `rwip_init()` marker is not Reset success. |",
        "| 4 | Prove real ingress | `03_real_ingress_consumed_pass.md` | Reset command must reach vendor ingress, not just sidecar scaffold. |",
        "| 5 | Prove real Reset event | `04_real_reset_event_pass.md` | Bytes must be `0E 04 01 03 0C 00` with synthetic disabled. |",
        "| 6 | Prove real RLV event | `05_real_rlv_event_pass.md` | RLV only after real Reset baseline. |",
        "| 7 | Repeat regression | `06_synthetic_off_repeated_regression_pass.md` | No stale markers or synthetic branch. |",
        "| 8 | Controlled BlueZ | `07_bluez_controlled_bringup_pass.md` | BlueZ only after repeated real Reset/RLV. |"
      ]
    },
    {
      "cell_type": "markdown",
      "metadata": {
        "language": "markdown"
      },
      "source": [
        "## 3. Commands That Are Safe Before Vendor Approval",
        "",
        "```bash",
        "bash scripts/check_ceva_sidecar_memory_contract.sh",
        "bash scripts/check_ceva_sidecar_no_synthetic_event.sh",
        "bash scripts/build_ceva_sidecar.sh",
        "make -C sidecar/ceva_bt52_sidecar clean",
        "```",
        "",
        "Before vendor approval, only static guards, sidecar scaffold builds, read-only vendor audits, and documentation are allowed."
      ]
    },
    {
      "cell_type": "markdown",
      "metadata": {
        "language": "markdown"
      },
      "source": [
        "## 4. Commands That Require Explicit Evidence Closure",
        "",
        "- Vendor runtime link requires `00_vendor_approval_closed.md`.",
        "- Runtime init proof requires approved runtime link evidence.",
        "- Real Reset/RLV proof requires runtime init and real ingress proof.",
        "- BlueZ bringup requires repeated Reset/RLV real pass evidence.",
        "",
        "The gate enforces this order through required evidence files and tokens."
      ]
    },
    {
      "cell_type": "markdown",
      "metadata": {
        "language": "markdown"
      },
      "source": [
        "## 5. Artifact Guard",
        "",
        "Never stage generated or protected files while closing Phase3 evidence:",
        "",
        "```text",
        "linux-bringup/dtb/chipyard-zcu104-fedora.(dtb|dts)",
        "scripts/run_ps_ddr_init.tcl",
        "generated-src/ target/ obj/",
        "*.bit *.dcp *.elf *.bin *.map *.dump *.log",
        "fw_payload initramfs.cpio stage_mark",
        "```"
      ]
    }
  ]
}
