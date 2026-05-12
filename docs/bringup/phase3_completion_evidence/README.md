{
  "cells": [
    {
      "cell_type": "markdown",
      "metadata": {
        "language": "markdown"
      },
      "source": [
        "# Phase3 Completion Evidence Directory",
        "",
        "This directory is reserved for real Phase3 completion evidence. Files in this directory are intentionally not created as PASS evidence until the corresponding hardware, vendor-runtime, and Linux RX proofs exist.",
        "",
        "The gate script is:",
        "",
        "```bash",
        "bash scripts/check_ceva_phase3_completion_gate.sh --status",
        "bash scripts/check_ceva_phase3_completion_gate.sh --require-pass",
        "```",
        "",
        "Current expected state before real vendor-runtime integration is `PHASE3_COMPLETION_GATE=INCOMPLETE`."
      ]
    },
    {
      "cell_type": "markdown",
      "metadata": {
        "language": "markdown"
      },
      "source": [
        "## Evidence Policy",
        "",
        "Do not create the required `*_pass.md` evidence files as placeholders. The completion gate checks both file presence and required PASS/marker/byte tokens, so an empty or weak file must not unlock Phase4.",
        "",
        "Templates are kept in `EVIDENCE_TEMPLATES.md` and do not satisfy the gate."
      ]
    }
  ]
}
