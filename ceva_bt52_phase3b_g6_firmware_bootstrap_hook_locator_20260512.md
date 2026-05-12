# CEVA BT5.2 Phase 3B-G6 Firmware / Bootstrap Hook Locator

## 1. Purpose

Phase 3B-G6 does not retry HCI Reset.

It answers only these four questions:

1. Where is the real consumer source code and function chain?
2. Does the current build and payload include it?
3. Do the current driver, open, or setup paths start it?
4. If not, where is the smallest bootstrap hook?

This document is the gate before returning to Phase 3B-G5, Phase 3B-E5-retry, and the later real Read Local Version PASS path.

## 2. Answer 1: where the real consumer actually is

### 2.1 The precise real HCI consumer chain is outside the workspace

The most concrete real HCI consumer chain found so far is in the external CEVA vendor software tree, not in the current workspace tree.

The bootstrap root is the external `rwip_init()` chain that Phase 0F already documented:

- `rwip_init(RESET_NO_ERROR)`
- `h4tl_init()`
- `hci_init()`
- `rwbt_init()`
- `rwble_init()`
- `rwip_driver_init(RWIP_INIT)`
- `rwip_reset()`

Workspace evidence for that chain is already recorded in [docs/bringup/ceva_bt52_phase0f_software_init_findings_phase0f0g_20260509_211507.md](docs/bringup/ceva_bt52_phase0f_software_init_findings_phase0f0g_20260509_211507.md#L116-L129).

The external read-only source audit then pinned the consumer and producer functions more precisely:

- Real bootstrap root: external vendor `rwip_init()` in the vendor `rwip.c` implementation.
- Real command ingress: external vendor H4TL RX handlers in the vendor `h4tl.c` implementation. Those handlers call `hci_cmd_received()`.
- Real HCI command dispatcher: external vendor `hci_cmd_received()` in the vendor `hci_tl.c` implementation.
- Real event producer: external vendor `hci_send_2_host()` in the vendor `hci.c` implementation.
- Real hardware-side low-level register init: external vendor `rwip_driver_init()` in the vendor `rwip_driver.c` implementation.

So the best current answer is:

The real HCI consumer is the vendor H4TL and HCI chain rooted at `rwip_init()`, not anything currently present in the workspace Linux driver.

### 2.2 The visible bluegrip mailbox code is not the current HCI Reset consumer

The external vendor tree also contains bluegrip mailbox code, including `mailbox_init()` and the mailbox driver implementation.

However, the visible mailbox implementation that was audited only initializes mailbox queues and handles messages such as:

- NVDS save request or ack
- assert error, info, and warning transport
- dump-data log transport

That mailbox code does not present a proven HCI Reset command consumer for the current 0x0C03 path.

So mailbox exists in the vendor platform tree, but the precise HCI consumer currently located by source audit is still the H4TL and HCI path, not the bluegrip mailbox path.

## 3. Answer 2: does the current build or payload include it

### 3.1 Current bitstream-side integration only points to CEVA RTL collateral

The current FPGA build script uses the ordered CEVA RTL file list, not the vendor software tree. Evidence: [scripts/build_bitstream_wsl.sh](scripts/build_bitstream_wsl.sh#L47-L55).

The current workspace-side CEVA generated directory contains only one file, the RTL order list. Evidence: [generated-src/ceva/rw_dm_top_rtl_files.list](generated-src/ceva/rw_dm_top_rtl_files.list).

That means the visible build-side CEVA integration in this workspace is a hardware RTL integration surface, not a software bootstrap integration surface.

### 3.2 Current payload rebuild packages Linux, OpenSBI, kernel modules, and smoke userspace only

The current payload rebuild path does the following:

- builds or copies kernel modules into initramfs, including `ceva_bt52.ko` at [rebuild_payload.sh](rebuild_payload.sh#L166)
- builds the userspace smoke binary at [rebuild_payload.sh](rebuild_payload.sh#L18) and [rebuild_payload.sh](rebuild_payload.sh#L179-L183)
- rebuilds the Linux Image
- embeds that Linux Image into OpenSBI `fw_payload.bin` via `FW_PAYLOAD_PATH="$LINUX_IMAGE"` at [rebuild_payload.sh](rebuild_payload.sh#L246)

What it does not do is equally important:

- it does not stage any visible vendor `rwip` or `h4tl` source artifact
- it does not stage any visible CEVA firmware blob
- it does not stage any visible vendor mailbox helper
- it does not copy any workspace file named like `rwip.c`, `h4tl.c`, `hci_tl.c`, or `em_map.h` because those files do not exist in the workspace tree

Local workspace file search for those implementation anchors returns no workspace files.

### 3.3 Current initramfs boot path only loads Linux modules and then runs the smoke tool

The init script currently:

- builds `phase25_ceva_params` at [linux-bringup/initramfs/rootfs/init](linux-bringup/initramfs/rootfs/init#L199-L205)
- insmods `ceva_bt52.ko` at [linux-bringup/initramfs/rootfs/init](linux-bringup/initramfs/rootfs/init#L214)
- waits for `hci0` at [linux-bringup/initramfs/rootfs/init](linux-bringup/initramfs/rootfs/init#L229-L243)
- immediately runs `/sbin/phase25_user_hci_smoke` at [linux-bringup/initramfs/rootfs/init](linux-bringup/initramfs/rootfs/init#L259-L266)

There is no visible step that loads or starts a vendor `rwip` or `h4tl` consumer between module load and smoke execution.

### 3.4 G6 conclusion for build and payload inclusion

No proven current build or payload path includes the real consumer chain that was located in the external vendor software tree.

The current build includes CEVA RTL collateral and the Linux-side glue path, but not a proven integrated vendor HCI consumer stack.

## 4. Answer 3: do current driver, open, or setup start it

No.

The current Linux driver does not visibly start the external real consumer chain.

### 4.1 `setup` does not start anything

`ceva_bt_setup()` only reads `DM_VERSION` and sets manufacturer 0x0057. Evidence: [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L1165-L1173).

### 4.2 `open` only performs MMIO hardware bring-up and marks the device running

`ceva_bt_open()`:

- calls `ceva_bt_hw_init()` at [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L1045)
- then sets `cbt->running = true` at [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L1049)

Current `ceva_bt_hw_init()` is a Linux-side MMIO bring-up path that resembles the register programming part of `rwip_driver_init()`, not a full software bootstrap. Evidence: [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L378-L429), [docs/bringup/ceva_bt52_phase0f_software_init_findings_phase0f0g_20260509_211507.md](docs/bringup/ceva_bt52_phase0f_software_init_findings_phase0f0g_20260509_211507.md#L104-L125).

### 4.3 `send_frame` only publishes into EM and asserts SWINT

The current send path writes the HCI command into EM, sets the command-ready flag, and asserts `DM_SWINT_REQ`. Evidence: [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L1066-L1119).

That is command publication, not bootstrap.

### 4.4 There is no visible runtime firmware loader or handshake in the driver

Searches of the current driver do not show a visible runtime firmware loader, `request_firmware`, `rwip_init`, `h4tl_init`, `rwip_reset`, or `hci_cmd_received` integration.

So the present driver callbacks do not start the real consumer.

## 5. Answer 4: where the smallest bootstrap hook belongs

### 5.1 Smallest runtime hook in the current codebase

If the real consumer is to be started from the current Linux path, the smallest runtime bootstrap hook belongs in `ceva_bt_open()`, immediately after `ceva_bt_hw_init()` returns successfully and before `cbt->running = true`.

That location is the smallest useful runtime slot because:

- `ceva_bt_hw_init()` has already reset and initialized DM or BT state there
- anything started earlier can be wiped by the open-time reset path
- `setup` is too shallow and currently only reads version metadata
- `probe` is too early and is only wiring callbacks such as [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L1260-L1263)
- `send_frame` is too late because the first HCI command may already race an unstarted consumer

### 5.2 Smallest image-inclusion hook in the current build flow

If that runtime hook needs a firmware blob, helper binary, or any vendor-side bootstrap asset, the smallest build or image hook belongs in `rebuild_payload.sh` before the Linux Image and OpenSBI payload rebuild steps, because that is where the current initramfs and final payload contents are assembled. Evidence: [rebuild_payload.sh](rebuild_payload.sh#L166-L246).

### 5.3 Important G6 caveat

The current precisely located real HCI consumer is the vendor H4TL and HCI chain.

The current Linux host path does not feed that chain directly. It writes into EM and asserts SWINT instead.

So the minimal hook is not “one more register write.”

The minimal hook must do one of two things with evidence:

1. start a real firmware-side consumer that is documented to drain the current EM command interface, or
2. add a non-synthetic bridge from the current Linux host publication path to the actual vendor consumer interface that was located in source audit

Without one of those two, merely toggling open or setup code will not prove real command consumption.

## 6. Final G6 answers in one block

### 6.1 Where is the real consumer source or function?

Outside the workspace, in the vendor software stack rooted at `rwip_init()`. The concrete command ingress is the vendor H4TL RX path calling `hci_cmd_received()`, and the concrete event producer is `hci_send_2_host()`.

### 6.2 Does the current build or payload include it?

No proven current build or payload path includes that consumer chain. The visible build includes CEVA RTL ordering, Linux, OpenSBI, `ceva_bt52.ko`, and the smoke tool, but not a proven vendor HCI consumer stack.

### 6.3 Do current driver, open, or setup start it?

No. `setup` reads version only. `open` performs MMIO bring-up only. `send_frame` only publishes EM command plus SWINT.

### 6.4 If not started, where is the smallest bootstrap hook?

The smallest runtime hook is in `ceva_bt_open()` after `ceva_bt_hw_init()` and before `cbt->running = true`. If any external firmware or helper asset must be included first, the smallest build hook is in `rebuild_payload.sh` before the payload rebuild is finalized.

That is the G6 stopping point. Only after a real consumer is included and started should the project return to:

- Phase 3B-G5: make command get consumed by the real consumer
- Phase 3B-E5-retry: real HCI Reset PASS
- Phase 3B-F later PASS work such as real Read Local Version