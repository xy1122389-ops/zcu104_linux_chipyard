# CEVA BT5.2 Phase 3B-G7 Real Consumer Route Decision

## 1. Purpose

Phase 3B-G7 is read-only.

Constraints for this phase:

- no driver code change
- no board run
- no payload rebuild
- no Git commit

The goal is to choose exactly one next route for the real CEVA-owned HCI Reset investigation:

- Route A: vendor H4TL or HCI consumer integration route
- Route B: current EM plus SWINT host path to vendor consumer bridge route
- Route C: prove that the current image lacks the vendor runtime, so real Reset cannot continue yet

This document makes that decision with no TBD.

## 2. Current boundary inside the workspace

### 2.1 Current Linux driver boundary is EM publication plus SWINT, not vendor runtime bootstrap

The current Linux driver boundary is unchanged from G6:

- `ceva_bt_open()` only calls hardware init and marks the device running. Evidence: [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L1037-L1055).
- `ceva_bt_send_frame()` packs an H4 command byte plus payload into the local EM command words, sets the command-ready flag, and asserts `DM_SWINT_REQ`. Evidence: [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L1075-L1159).
- `ceva_bt_setup()` only reads `DM_VERSION` and sets manufacturer metadata. Evidence: [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L1165-L1174).

So the current in-workspace host path publishes one command into EM and nudges the DM with SWINT. It does not start a vendor software runtime.

### 2.2 Current payload assembly path contains Linux, OpenSBI, modules, and smoke only

The current payload rebuild path stages kernel modules into initramfs, including `ceva_bt52.ko`, and then wraps the rebuilt Linux Image into OpenSBI `fw_payload.bin`. Evidence: [rebuild_payload.sh](rebuild_payload.sh#L135-L170), [rebuild_payload.sh](rebuild_payload.sh#L239-L267).

The current init path then loads `bluetooth.ko`, insmods `ceva_bt52.ko`, waits for `hci0`, and immediately runs the userspace smoke tool. Evidence: [linux-bringup/initramfs/rootfs/init](linux-bringup/initramfs/rootfs/init#L175-L272).

There is still no visible workspace inclusion or startup step for vendor `rwip`, `h4tl`, `hci_tl`, or a vendor controller firmware blob.

## 3. Vendor real consumer boundary outside the workspace

### 3.1 The vendor consumer is a baremetal or RTOS-style controller runtime, not a Linux-kernel-direct-call helper

Read-only audit of the external vendor software tree shows that the real consumer sits inside a controller runtime rooted at `rwip_init()` and `rwip_reset()`, not in a small standalone helper function.

The audited chain is consistent with the earlier G6 locator and the existing Phase 0F research note: [ceva_bt52_phase3b_g6_firmware_bootstrap_hook_locator_20260512.md](ceva_bt52_phase3b_g6_firmware_bootstrap_hook_locator_20260512.md), [docs/bringup/ceva_bt52_phase0f_software_init_findings_phase0f0g_20260509_211507.md](docs/bringup/ceva_bt52_phase0f_software_init_findings_phase0f0g_20260509_211507.md#L116-L129).

The external source audit showed these runtime dependencies before command handling is meaningful:

- `rwip_init()` calls `ke_init()` and multiple `ke_mem_init()` heap initializers, then `h4tl_init()`, `hci_init()`, `rwbt_init()`, `rwble_init()`, and `rwip_driver_init()`.
- `rwip_reset()` wraps reset under `GLOBAL_INT_DISABLE()` and `GLOBAL_INT_RESTORE()`, flushes timers with `ke_timer_flush()`, reinitializes `co_djob`, `co_time`, HCI, scheduler blocks, and message state.
- `hci_cmd_received()` dispatches commands to vendor tasks such as `TASK_LM`, `TASK_LLM`, `TASK_DBG`, and link-specific controller tasks.

That is a controller firmware runtime shape, not a Linux HCI driver ABI shape.

### 3.2 The vendor ingress is H4TL byte-stream RX, not the current EM plus SWINT command slot

The external H4TL interface is explicitly defined as an H4 UART transport layer and takes a `struct rwip_eif_api` with `read`, `write`, `flow_on`, and `flow_off` callbacks.

The external H4TL implementation then:

- reads incoming bytes through `ext_if->read()` into RX buffers
- parses H4 command headers and payloads
- allocates payload buffers with `ke_malloc()`
- calls `hci_cmd_received(opcode, length, payload)` when a command has been received

So the audited vendor consumer input contract is an H4TL byte stream, not the current workspace EM command words plus a SWINT poke.

### 3.3 The vendor egress is HCI transport output, not the current EM event-ready convention

The external event producer path is also transport-oriented:

- internal controller code calls `hci_send_2_host()`
- the HCI transport layer forwards the packet with `h4tl_write()`
- H4TL then emits bytes through `ext_if->write()`

So the audited vendor event return path is HCI transport output, not the workspace driver's current expectation that a CEVA-side owner will publish an event into EM and raise the matching ready condition.

## 4. Route evaluation

### 4.1 Route A is not the right next route

Route A would mean integrating the vendor H4TL or HCI consumer directly into the current Linux-side environment as if it were a callable software library.

That is not the smallest or safest next step because the audited vendor consumer depends on:

- vendor kernel and message runtime (`ke_*`)
- vendor timer and scheduling runtime (`ke_timer_*`, `co_djob`, `co_time`, scheduler blocks)
- vendor global interrupt control
- vendor external-interface abstraction `rwip_eif_api`
- vendor controller task graph and state machines

Therefore Route A is not a minimal Linux-driver integration move. It is effectively a controller-runtime port or a separate firmware integration problem.

### 4.2 Route B is the long-term technical shape, but it is not the correct next route today

Route B is closer to the real architecture than Route A because it respects that the current Linux host boundary and the vendor consumer boundary are different objects.

However, Route B is still not the correct next route today because the current image does not prove that the vendor runtime is present or started at all.

Without a proven included vendor runtime, an EM-to-vendor bridge is still speculative. There is nothing proven in the current payload to receive that bridge on the far side.

In addition, Route B is not a tiny shim. The audited boundary mismatch is two-sided:

- ingress mismatch: current host side publishes EM plus SWINT, while the vendor consumer expects H4TL RX byte stream semantics
- egress mismatch: vendor side returns HCI packets through H4TL TX, while the current driver waits for EM event publication conventions

So Route B is the likely future engineering direction only after vendor runtime presence is proven and a supported integration surface exists.

### 4.3 Route C is the correct G7 decision

Route C is the correct next decision now.

The current evidence supports one narrow conclusion: the present workspace build and payload do not prove that the vendor real-consumer runtime is included or started, so the project should not keep trying to force a real HCI Reset PASS from the current image.

This is also consistent with the frozen E1 to E5 result: better host-side IRQ handling and better register fidelity did not produce a real event. Evidence: [ceva_bt52_phase3b_e1_e5_diagnosis_20260512.md](ceva_bt52_phase3b_e1_e5_diagnosis_20260512.md).

## 5. Final G7 decision

Selected route: Route C.

Decision statement:

The current integrated image lacks a proven started vendor runtime that can consume the real command and produce the matching real event, so real Reset should stop here until vendor runtime inclusion is proven. If the project later gains that runtime, the follow-on integration direction should resemble Route B, not Route A.

## 6. Next phase

Next phase name: Phase 3B-G8 Vendor Runtime Inclusion Gate.

Scope of that next phase is not to retry Reset. Scope is to prove, with read-only build and image evidence, whether any vendor runtime asset or bootstrap path actually exists in the shipped image. Only after that gate passes should a bridge or bootstrap implementation phase begin.

## 7. Direct answers requested by G7

1. Is the vendor consumer directly callable from the Linux kernel driver? No. The audited entry points belong to a controller runtime with vendor kernel, memory, timer, task, interrupt, and transport abstractions.
2. What runtime does it depend on? Vendor `ke_*` memory and message runtime, timer and scheduling blocks, global interrupt control, `rwip_driver_init`, controller tasks, and `rwip_eif_api` transport callbacks.
3. Does it consume H4TL byte stream or the current EM plus SWINT command path? It consumes H4TL byte stream.
4. How does `hci_send_2_host()` return events? Through the vendor HCI transport path into `h4tl_write()` and then the external interface write callback.
5. Which route is recommended now? Route C.
6. What is the next phase name? Phase 3B-G8 Vendor Runtime Inclusion Gate.

That is the G7 stopping point. No PASS claim should be made for real Reset on the current image after this decision.