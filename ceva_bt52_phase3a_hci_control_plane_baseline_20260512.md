# CEVA BT5.2 Phase 3A-A HCI Control-Plane Baseline

## 1. Frozen baseline

- Commit: 4f2dadcf075007982e36249dbb5d7fdd9e967303
- Tag: phase2.5-userspace-hci-smoke-pass-20260512
- Runbook: [docs/bringup/ceva_bt52_phase25_runbook_20260512.md](docs/bringup/ceva_bt52_phase25_runbook_20260512.md)
- Difficulties: [docs/bringup/ceva_bt52_phase25_difficulties_and_lessons_20260512.md](docs/bringup/ceva_bt52_phase25_difficulties_and_lessons_20260512.md)
- Final PASS log: [logs/phase25_rerun_20260512_140511/run.log](logs/phase25_rerun_20260512_140511/run.log)

Phase 2.5 PASS evidence is present in the frozen rerun log: kernel-side synthetic markers at [logs/phase25_rerun_20260512_140511/run.log](logs/phase25_rerun_20260512_140511/run.log#L229-L231) and userspace smoke markers at [logs/phase25_rerun_20260512_140511/run.log](logs/phase25_rerun_20260512_140511/run.log#L304-L330).

## 2. Phase 2.5 proved what

Phase 2.5 proved this control-plane chain:

initramfs userspace
-> hci0
-> ceva_bt52 driver
-> synthetic Command Complete
-> userspace receives HCI Reset and Read Local Version results

More concretely, the frozen baseline proves that [linux-bringup/initramfs/phase25_user_hci_smoke.c](linux-bringup/initramfs/phase25_user_hci_smoke.c) can send HCI Reset and Read Local Version to hci0, and that [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c) can synthesize matching HCI events back into the Linux Bluetooth core.

## 3. Phase 2.5 did not prove what

- It did not prove that real CEVA firmware is running.
- It did not prove that the real mailbox or event path is operational end-to-end.
- It did not prove RF or VPHY functionality.
- It did not prove BlueZ scan, pair, or connect flows.
- It did not prove that a phone can connect to this platform.

## 4. Userspace HCI smoke behavior

| Item | Current behavior | Evidence |
|---|---|---|
| socket channel | The baseline path prefers HCI_CHANNEL_USER when hci0 is running but not HCI_UP. It falls back to HCI_CHANNEL_RAW only if USER bind fails. | [linux-bringup/initramfs/phase25_user_hci_smoke.c](linux-bringup/initramfs/phase25_user_hci_smoke.c#L666-L674) |
| HCI_FILTER | HCI_FILTER is skipped on HCI_CHANNEL_USER. setsockopt is only attempted on non-USER channels. | [linux-bringup/initramfs/phase25_user_hci_smoke.c](linux-bringup/initramfs/phase25_user_hci_smoke.c#L397-L416) |
| H4 packet type | The smoke keeps the H4 packet type prefix and sends HCI_COMMAND_PKT before the command header. | [linux-bringup/initramfs/phase25_user_hci_smoke.c](linux-bringup/initramfs/phase25_user_hci_smoke.c#L589-L590) |
| Reset opcode | 0x0C03, derived by HCI_OPCODE from OGF_HOST_CTL 0x03 and OCF_RESET 0x0003. | [linux-bringup/initramfs/phase25_user_hci_smoke.c](linux-bringup/initramfs/phase25_user_hci_smoke.c#L38-L44) |
| Read Local Version opcode | 0x1001, derived by HCI_OPCODE from OGF_INFO_PARAM 0x04 and OCF_READ_LOCAL_VERSION 0x0001. | [linux-bringup/initramfs/phase25_user_hci_smoke.c](linux-bringup/initramfs/phase25_user_hci_smoke.c#L40-L45) |
| event filtering | Userspace filters events after recv. It accepts HCI_EV_CMD_STATUS and HCI_EV_CMD_COMPLETE, then matches the returned opcode itself. | [linux-bringup/initramfs/phase25_user_hci_smoke.c](linux-bringup/initramfs/phase25_user_hci_smoke.c#L496-L512), [linux-bringup/initramfs/phase25_user_hci_smoke.c](linux-bringup/initramfs/phase25_user_hci_smoke.c#L520-L547) |

Error and timeout reporting also stays in userspace. Socket, bind, and setsockopt failures are printed via print_errno_result as PHASE25_USER_* rc and errno lines, while recv-side failures and timeouts are printed via print_command_recv with evt, opcode, and status fields. PASS markers are emitted in main after each command and at final summary. Evidence: [linux-bringup/initramfs/phase25_user_hci_smoke.c](linux-bringup/initramfs/phase25_user_hci_smoke.c#L181-L183), [linux-bringup/initramfs/phase25_user_hci_smoke.c](linux-bringup/initramfs/phase25_user_hci_smoke.c#L428-L434), [linux-bringup/initramfs/phase25_user_hci_smoke.c](linux-bringup/initramfs/phase25_user_hci_smoke.c#L555-L556), [linux-bringup/initramfs/phase25_user_hci_smoke.c](linux-bringup/initramfs/phase25_user_hci_smoke.c#L688-L717).

## 5. Kernel synthetic responder boundary

The synthetic boundary is implemented by the driver send path in [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L923-L999), the init-command helper switch in [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L554-L586), and the event injection helper in [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L306-L333).

| HCI command | Opcode | Current response | Real CEVA involved? | Status |
|---|---:|---|---|---|
| HCI Reset | 0x0C03 | Command Complete, status 0x00 | No | Supported |
| Read Local Version | 0x1001 | Command Complete, status 0x00, hci_ver 0x0B, hci_rev 0x0520, lmp_ver 0x0B, manufacturer 0x0057, lmp_subver 0x0520 | No | Supported |
| Read Local Features | 0x1003 | Command Complete, status 0x00, fixed zero feature payload | No | Supported |
| Read BD_ADDR | 0x1009 | Command Complete, status 0x00, synthetic BD_ADDR payload | No | Supported |
| Read Local Commands | 0x1002 | Command Complete, status 0x00, zeroed local-command bitmap payload | No | Supported |
| Set Event Mask | 0x0C01 | Command Complete, status 0x00 | No | Supported |
| Read Buffer Size | 0x1005 | Command Complete, status 0x00, fixed buffer-size payload | No | Supported |
| Read Class of Device | 0x0C23 | Command Complete, status 0x00, class 0x000000 | No | Supported |
| Read Local Name | 0x0C14 | Command Complete, status 0x00, name CEVA-BT52 | No | Supported |
| Read Voice Setting | 0x0C25 | Command Complete, status 0x00, voice setting 0x0060 | No | Supported |
| Read Num Supported IAC | 0x0C38 | Command Complete, status 0x00, count 0x01 | No | Supported |
| Read Current IAC LAP | 0x0C39 | Generic Command Complete, status 0x00 only | No | Supported |
| Set Event Filter | 0x0C05 | Generic Command Complete, status 0x00 only | No | Supported |
| Write Connection Accept Timeout | 0x0C16 | Generic Command Complete, status 0x00 only | No | Supported |
| Read Page Scan Activity | 0x0C1B | Command Complete, status 0x00, fixed scan activity payload | No | Supported |
| Read Page Scan Type | 0x0C46 | Command Complete, status 0x00, type 0x00 | No | Supported |
| Others | N/A | No synthetic event is built. The driver still writes the command into EM and asserts SWINT_REQ, but the default synthetic switch returns without generating a reply. | No | Unsupported |

hci0 is allocated and registered in probe by hci_alloc_dev and hci_register_dev, with open, close, send, and setup callbacks installed before registration. Evidence: [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L1086-L1114).

## 6. Current data path diagram

userspace phase25_user_hci_smoke
-> AF_BLUETOOTH HCI socket
-> hci0
-> Linux Bluetooth core
-> ceva_bt_send_frame
-> write EM_CMD_WORD and set EM_CMD_FLAG_WORD
-> assert DM_SWINT_REQ
-> phase25 synthetic response queue or init-command helper switch
-> ceva_bt_recv_event_buf
-> hci_recv_frame
-> userspace recv loop sees HCI_EV_CMD_STATUS or HCI_EV_CMD_COMPLETE and matches opcode

There is also a separate real IRQ-driven receive path in the driver: [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L834-L881). That path reads EM_EVT_WORD through rx_work after dm_sw_irq, but the Phase 2.5 proven PASS path does not require that path to return Reset or Read Local Version.

## 7. Current gap to real CEVA firmware or mailbox path

- There is still no proven CEVA firmware boot or init sequence in the frozen Phase 2.5 baseline.
- There is still no proven EM mailbox command ring running against real firmware.
- There is still no proven CEVA event ring returning real Command Complete events.
- The driver does write commands into EM and assert SWINT_REQ, but the supported Phase 2.5 responses are synthesized inside Linux instead of being read back from real firmware.
- The driver has code for a real IRQ and EM event path, but Phase 2.5 did not prove that path as the source of the PASS markers.
- ceva_bt_open performs hardware bring-up and CLKN polling, not a real firmware load or firmware boot handshake. Evidence: [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L242-L291), [linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c](linux-bringup/kernel/ceva-bt52-driver/ceva_bt52.c#L888-L906).

## 8. Recommended Phase 3A-B next step

Phase 3A-B should do the following without widening scope into RF or BlueZ:

1. Keep an explicit supported-opcode table for every synthetic response.
2. Add clear logs for unsupported opcodes so timeout root cause is obvious.
3. Extend the userspace smoke to support repeat=N repeated control-plane testing.
4. Print opcode, event code, and status for every command and every received event.
5. Keep BlueZ scan, pair, and connect out of scope until the real CEVA command or event path is proven.

## 9. Acceptance criteria

Phase 3A-A PASS means:

- This document lists the current userspace socket and channel behavior.
- This document lists the current synthetic responder opcode boundary.
- This document makes the gap between synthetic response flow and real CEVA path explicit.
- No functional code is modified.
- No synthesis, Vivado run, board test, J-Link session, or payload rebuild is performed.