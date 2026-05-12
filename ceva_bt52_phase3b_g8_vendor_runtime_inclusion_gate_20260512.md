# CEVA BT5.2 Phase 3B-G8 Vendor Runtime Inclusion Gate

## 1. Purpose

This phase decides whether the external CEVA vendor runtime can be included and started in the current ZCU104 + Chipyard + Linux payload flow.

This phase does not run real HCI Reset.

This phase does not add synthetic replies.

This phase does not modify the driver, RTL, or payload image.

G8 is a read-only inclusion gate plus pre-integration decision point.

## 2. Current conclusion from G7

Route C is the current decision.

The real HCI command consumer is not a simple Linux-kernel-callable helper.

The identified vendor-side chain is:

```text
rwip_init / rwip_reset
  -> h4tl_init
  -> hci_cmd_received
  -> hci_send_2_host
```

That chain lives in the external vendor software tree and depends on vendor runtime pieces such as `ke_*`, timer and scheduler blocks, interrupt control, and `rwip_eif_api` transport callbacks. Evidence: [ceva_bt52_phase3b_g6_firmware_bootstrap_hook_locator_20260512.md](ceva_bt52_phase3b_g6_firmware_bootstrap_hook_locator_20260512.md), [ceva_bt52_phase3b_g7_real_consumer_route_decision_20260512.md](ceva_bt52_phase3b_g7_real_consumer_route_decision_20260512.md).

The current workspace path remains EM command publication plus SWINT, not vendor runtime bootstrap.

## 3. Current workspace pre-closeout state

### 3.1 Source and documentation changes that remain candidate commit material

The current candidate source or document surface is limited to:

- [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c)
- [scripts/linux_boot_phase2_capture.gdb](scripts/linux_boot_phase2_capture.gdb)
- [scripts/linux_boot_phase2_launch.gdb](scripts/linux_boot_phase2_launch.gdb)
- [ceva_bt52_phase3b_e1_e5_diagnosis_20260512.md](ceva_bt52_phase3b_e1_e5_diagnosis_20260512.md)
- [ceva_bt52_phase3b_f_firmware_bootstrap_mailbox_audit_20260512.md](ceva_bt52_phase3b_f_firmware_bootstrap_mailbox_audit_20260512.md)
- [ceva_bt52_phase3b_g6_firmware_bootstrap_hook_locator_20260512.md](ceva_bt52_phase3b_g6_firmware_bootstrap_hook_locator_20260512.md)
- [ceva_bt52_phase3b_g7_real_consumer_route_decision_20260512.md](ceva_bt52_phase3b_g7_real_consumer_route_decision_20260512.md)
- [ceva_bt52_phase3b_g8_vendor_runtime_inclusion_gate_20260512.md](ceva_bt52_phase3b_g8_vendor_runtime_inclusion_gate_20260512.md)

### 3.2 Generated or temporary files that are explicitly not commit material

The pre-closeout cleanup removed or restored generated outputs that must not be committed, including initramfs artifacts, `fw_payload.bin`, temporary userspace smoke output, and local build logs.

### 3.3 Protected local files that must stay out of commit

These local files are intentionally preserved in the workspace and must not be pulled into a documentation-only or source-only commit:

- [linux-bringup/dtb/chipyard-zcu104-fedora.dtb](linux-bringup/dtb/chipyard-zcu104-fedora.dtb)
- [linux-bringup/dtb/chipyard-zcu104-fedora.dts](linux-bringup/dtb/chipyard-zcu104-fedora.dts)
- [scripts/run_ps_ddr_init.tcl](scripts/run_ps_ddr_init.tcl)

## 4. Exact G8 gate questions

G8 should answer these questions with read-only evidence:

1. Does the current repository and build flow contain any real inclusion path for the external vendor runtime source, blob, archive, or helper image?
2. If an inclusion path exists, what exact build rule, copy rule, or image-packaging step brings it into the final shipped payload?
3. If a payload inclusion path exists, what exact startup hook would start that runtime in the current boot flow?
4. Does the identified runtime consume the current EM plus SWINT boundary directly, or would a bridge still be required?
5. If a bridge would still be required, is there any already-integrated runtime endpoint on the far side, or is the runtime itself still absent?
6. What is the minimum non-speculative evidence that would prove vendor runtime inclusion and startup without claiming a real Reset PASS?

## 5. Required read-only audit inputs

G8 should use only read-only evidence from these surfaces:

- workspace build and packaging scripts such as [rebuild_payload.sh](rebuild_payload.sh)
- initramfs boot path such as [linux-bringup/initramfs/rootfs/init](linux-bringup/initramfs/rootfs/init)
- current Linux driver boundaries in [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c)
- external vendor runtime sources already identified in G6 and G7
- workspace searches for `rwip`, `h4tl`, `hci_cmd_received`, `hci_send_2_host`, `request_firmware`, `mailbox`, and `rwip_eif_api`
- any existing image-staging or firmware-loader hooks already present in the tree

## 6. Gate pass criteria

G8 passes only if all of the following can be named with direct evidence:

- the exact vendor runtime asset or source package to be included
- the exact build inclusion step that brings it into the current image flow
- the exact final image location or payload packaging surface where it lands
- the exact startup hook that would start it in the current boot sequence
- the exact ingress and egress boundary compatibility, or the exact remaining bridge that would still be required

If any one of those items remains speculative, the gate does not pass.

## 7. Gate fail criteria

G8 fails if one or more of these conditions hold:

- the vendor runtime only exists outside the workspace with no current inclusion path
- the workspace only contains CEVA RTL collateral, MMIO glue, docs, and capture logic
- no build rule stages vendor runtime assets into initramfs, Linux, OpenSBI, or another shipped image surface
- no startup hook exists that could start the runtime in the current boot flow
- the runtime boundary mismatch remains unresolved and there is no integrated far-side endpoint to bridge to

A G8 fail result keeps the project on Route C and blocks any further real Reset attempt on the current image.

## 8. Expected G8 outputs

The expected outputs of G8 are:

- one frozen document stating whether vendor runtime inclusion is currently real, absent, or still speculative
- one exact list of missing assets or missing hooks if the gate fails
- one exact next phase name based on the gate result

If the gate passes, the next phase would be an inclusion or integration design phase.

If the gate fails, the next phase remains an architectural stop with Route C still in force.

## 9. Non-goals

G8 does not do any of the following:

- no board run
- no payload rebuild
- no driver modification
- no RTL modification
- no Vivado run
- no synthetic responder expansion
- no real HCI Reset retry

## 10. Starting baseline for G8

G8 starts from these already-frozen facts:

- E1 to E5 host-side fixes were insufficient. Evidence: [ceva_bt52_phase3b_e1_e5_diagnosis_20260512.md](ceva_bt52_phase3b_e1_e5_diagnosis_20260512.md)
- F established the consumer-gap pivot. Evidence: [ceva_bt52_phase3b_f_firmware_bootstrap_mailbox_audit_20260512.md](ceva_bt52_phase3b_f_firmware_bootstrap_mailbox_audit_20260512.md)
- G6 located the real external consumer chain and smallest possible hook area. Evidence: [ceva_bt52_phase3b_g6_firmware_bootstrap_hook_locator_20260512.md](ceva_bt52_phase3b_g6_firmware_bootstrap_hook_locator_20260512.md)
- G7 selected Route C and deferred all real Reset work behind a vendor-runtime inclusion proof gate. Evidence: [ceva_bt52_phase3b_g7_real_consumer_route_decision_20260512.md](ceva_bt52_phase3b_g7_real_consumer_route_decision_20260512.md)

That is the G8 starting point. The next move is not implementation. The next move is proof.