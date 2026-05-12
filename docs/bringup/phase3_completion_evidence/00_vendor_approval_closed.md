{
  "cells": [
    {
      "cell_type": "markdown",
      "metadata": {
        "language": "markdown",
        "id": "phase3-approval-00"
      },
      "source": [
        "# Phase3 Vendor Approval Closed",
        "",
        "PHASE3_VENDOR_APPROVAL=PASS",
        "APPROVED_SCOPE=local-build",
        "NO_VENDOR_SOURCE_COMMITTED=PASS",
        "",
        "## Scope",
        "",
        "The user granted permission to continue Phase3 recovery work and complete all tasks autonomously inside this local workspace.",
        "",
        "This approval covers local analysis, local build attempts, local linking experiments, local hardware bring-up, and local evidence collection against the CEVA BT5.2 collateral paths already present on this machine.",
        "",
        "It does not authorize committing CEVA vendor source, restricted blobs, generated vendor binaries, or proprietary vendor-derived files into the repository.",
        "",
        "## Guardrails",
        "",
        "- Keep vendor assets external to git unless the user explicitly asks otherwise and the asset is legally redistributable.",
        "- Prefer local adapter/boundary code in this repository over copying vendor source.",
        "- Evidence files may record commands, checksums, symbol names, marker values, and HCI byte results, but must not embed restricted vendor source.",
        "- Phase3 completion still requires real vendor-runtime link, init, ingress, Reset, RLV, regression, and controlled BlueZ evidence."
      ]
    }
  ]
}
