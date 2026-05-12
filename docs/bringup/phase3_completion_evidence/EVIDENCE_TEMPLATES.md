{
  "cells": [
    {
      "cell_type": "markdown",
      "metadata": {
        "language": "markdown"
      },
      "source": [
        "# Phase3 Completion Evidence Templates",
        "",
        "This notebook contains templates only. Do not rename or copy a template into a required `*_pass.md` file unless the corresponding proof has actually been run and reviewed.",
        "",
        "Required evidence files are checked by `scripts/check_ceva_phase3_completion_gate.sh`. Each real evidence file must contain the required PASS tokens and supporting log/marker/byte evidence."
      ]
    },
    {
      "cell_type": "markdown",
      "metadata": {
        "language": "markdown"
      },
      "source": [
        "## 00 Vendor Approval Closed",
        "",
        "Target file: `00_vendor_approval_closed.md`",
        "",
        "Required tokens:",
        "",
        "```text",
        "PHASE3_VENDOR_APPROVAL=PASS",
        "APPROVED_SCOPE=local-build",
        "```",
        "",
        "Required content:",
        "",
        "- Approval owner and date.",
        "- Approved vendor root or blob identifiers.",
        "- Explicit statement that local build or local link is allowed.",
        "- Explicit statement that restricted vendor source/binary is not committed to this repo unless separately approved."
      ]
    },
    {
      "cell_type": "markdown",
      "metadata": {
        "language": "markdown"
      },
      "source": [
        "## 01 Vendor Runtime Link Pass",
        "",
        "Target file: `01_vendor_runtime_link_pass.md`",
        "",
        "Required tokens:",
        "",
        "```text",
        "PHASE3_VENDOR_RUNTIME_LINK=PASS",
        "NO_VENDOR_SOURCE_COMMITTED=PASS",
        "```",
        "",
        "Required content:",
        "",
        "- Exact local build command.",
        "- Link map or symbol proof for approved runtime pieces.",
        "- Proof that `rwip`, `rwip_driver`, `hci`, `h4tl`, `ke`, `co`, `sch`, register access, and platform glue are represented by approved inputs.",
        "- `git status --short` excerpt proving restricted vendor files are not staged/committed."
      ]
    },
    {
      "cell_type": "markdown",
      "metadata": {
        "language": "markdown"
      },
      "source": [
        "## 02 RWIP Init And Driver Init Pass",
        "",
        "Target file: `02_rwip_init_and_driver_init_pass.md`",
        "",
        "Required tokens:",
        "",
        "```text",
        "PHASE3_RWIP_INIT=PASS",
        "PHASE3_RWIP_DRIVER_INIT=PASS",
        "SIDECAR_POST_RWIP_INIT",
        "SIDECAR_POST_RWIP_DRIVER_INIT",
        "```",
        "",
        "Required content:",
        "",
        "- Marker dump showing non-stale `SIDECAR_POST_RWIP_INIT` and `SIDECAR_POST_RWIP_DRIVER_INIT`.",
        "- Runtime log or debugger proof tying markers to current run.",
        "- Register side effects expected from `rwip_driver_init()` if applicable."
      ]
    },
    {
      "cell_type": "markdown",
      "metadata": {
        "language": "markdown"
      },
      "source": [
        "## 03 Real Ingress Consumed Pass",
        "",
        "Target file: `03_real_ingress_consumed_pass.md`",
        "",
        "Required tokens:",
        "",
        "```text",
        "PHASE3_REAL_INGRESS_CONSUMED=PASS",
        "SYNTHETIC_DISABLED=PASS",
        "HCI_RESET_CMD=03 0C 00",
        "SIDECAR_CMD_CONSUMED",
        "```",
        "",
        "Required content:",
        "",
        "- Linux command publish evidence from EM command window.",
        "- Vendor ingress seam marker such as `hci_cmd_received()` or documented equivalent.",
        "- Sequence or run-id proof excluding stale command markers.",
        "- Proof that synthetic responder path was disabled."
      ]
    },
    {
      "cell_type": "markdown",
      "metadata": {
        "language": "markdown"
      },
      "source": [
        "## 04 Real Reset Event Pass",
        "",
        "Target file: `04_real_reset_event_pass.md`",
        "",
        "Required tokens:",
        "",
        "```text",
        "PHASE3_REAL_RESET_EVENT=PASS",
        "SYNTHETIC_DISABLED=PASS",
        "RESET_CC_BYTES=0E 04 01 03 0C 00",
        "LINUX_RX_REAL_EVENT",
        "```",
        "",
        "Required content:",
        "",
        "- EM event window byte dump showing Reset Command Complete.",
        "- Sidecar egress marker chain.",
        "- Linux RX marker/log proving the event entered the Linux HCI RX path.",
        "- Proof that bytes came from real vendor runtime, not synthetic code."
      ]
    },
    {
      "cell_type": "markdown",
      "metadata": {
        "language": "markdown"
      },
      "source": [
        "## 05 Real RLV Event Pass",
        "",
        "Target file: `05_real_rlv_event_pass.md`",
        "",
        "Required tokens:",
        "",
        "```text",
        "PHASE3_REAL_RLV_EVENT=PASS",
        "SYNTHETIC_DISABLED=PASS",
        "RLV_CC_PREFIX=0E 0C 01 01 10 00",
        "LINUX_RX_REAL_EVENT",
        "```",
        "",
        "Required content:",
        "",
        "- Read Local Version command evidence `01 10 00`.",
        "- Real Command Complete prefix and version payload.",
        "- Linux RX marker/log proof.",
        "- Reset baseline reference proving RLV was run after real Reset success."
      ]
    },
    {
      "cell_type": "markdown",
      "metadata": {
        "language": "markdown"
      },
      "source": [
        "## 06 Synthetic-Off Repeated Regression Pass",
        "",
        "Target file: `06_synthetic_off_repeated_regression_pass.md`",
        "",
        "Required tokens:",
        "",
        "```text",
        "PHASE3_SYNTHETIC_OFF_REGRESSION=PASS",
        "RESET_RLV_REPEAT_COUNT=",
        "```",
        "",
        "Required content:",
        "",
        "- Repeat count and run tags.",
        "- Reset/RLV evidence references for every run.",
        "- No stale marker ambiguity.",
        "- No generated artifact staging."
      ]
    },
    {
      "cell_type": "markdown",
      "metadata": {
        "language": "markdown"
      },
      "source": [
        "## 07 BlueZ Controlled Bringup Pass",
        "",
        "Target file: `07_bluez_controlled_bringup_pass.md`",
        "",
        "Required tokens:",
        "",
        "```text",
        "PHASE3_BLUEZ_CONTROLLED_BRINGUP=PASS",
        "PHASE3_RESET_RLV_BASELINE_VERIFIED=PASS",
        "```",
        "",
        "Required content:",
        "",
        "- Reset/RLV repeated real baseline reference.",
        "- BlueZ command sequence and logs.",
        "- Explicit statement that BlueZ was not used to mask controller-level failures.",
        "- Controlled scan/pair/connect evidence if run."
      ]
    }
  ]
}
