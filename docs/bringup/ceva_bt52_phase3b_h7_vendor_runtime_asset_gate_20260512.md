# CEVA BT5.2 Phase 3B-H7 Vendor Runtime Asset Gate

## 1. Goal

H7 verifies whether the CEVA BT5.2 vendor software and hardware collateral is present enough to support a future real runtime integration plan.

This phase is read-only. It does not copy vendor source into this repository, does not link vendor code, does not produce a runtime image, does not edit payload, does not edit RTL, and does not claim a real controller PASS.

## 2. Vendor Roots Checked

| Root | Path | Result |
|---|---|---|
| CEVA SW | `/mnt/e/桌面/CEVA_BT5.2/home/user007/project/CEVA_BT5.2/rw-btdm-blehost-sw-v11_0_3` | Present |
| CEVA HW | `/mnt/e/桌面/CEVA_BT5.2/home/user007/project/CEVA_BT5.2/rw-dm-hw-v11_00_03` | Present |

## 3. Key Files Verified

| Asset | Path | Result |
|---|---|---|
| RWIP core | `/mnt/e/桌面/CEVA_BT5.2/home/user007/project/CEVA_BT5.2/rw-btdm-blehost-sw-v11_0_3/src/modules/rwip/src/rwip.c` | Present |
| RWIP driver | `/mnt/e/桌面/CEVA_BT5.2/home/user007/project/CEVA_BT5.2/rw-btdm-blehost-sw-v11_0_3/src/modules/rwip/src/rwip_driver.c` | Present |
| H4 transport layer | `/mnt/e/桌面/CEVA_BT5.2/home/user007/project/CEVA_BT5.2/rw-btdm-blehost-sw-v11_0_3/src/modules/h4tl/src/h4tl.c` | Present |
| HCI transport | `/mnt/e/桌面/CEVA_BT5.2/home/user007/project/CEVA_BT5.2/rw-btdm-blehost-sw-v11_0_3/src/ip/hci/src/hci_tl.c` | Present |
| HCI core | `/mnt/e/桌面/CEVA_BT5.2/home/user007/project/CEVA_BT5.2/rw-btdm-blehost-sw-v11_0_3/src/ip/hci/src/hci.c` | Present |
| HCI message helpers | `/mnt/e/桌面/CEVA_BT5.2/home/user007/project/CEVA_BT5.2/rw-btdm-blehost-sw-v11_0_3/src/ip/hci/src/hci_msg.c` | Present |
| REFIP arch main | `/mnt/e/桌面/CEVA_BT5.2/home/user007/project/CEVA_BT5.2/rw-btdm-blehost-sw-v11_0_3/src/plf/refip/src/arch/main/arch_main.c` | Present |
| DM RTL top | `/mnt/e/桌面/CEVA_BT5.2/home/user007/project/CEVA_BT5.2/rw-dm-hw-v11_00_03/HW/IPs/Src/DM/rw_dm_top/verilog/rtl/rw_dm_top.v` | Present |

## 4. Header Anchors

| Header | Relative location under CEVA SW root |
|---|---|
| `em_map.h` | `src/ip/em/api/em_map.h` |
| `hci.h` | `src/ip/hci/api/hci.h` |
| `h4tl.h` | `src/modules/h4tl/api/h4tl.h` |
| `rwip.h` | `src/modules/rwip/api/rwip.h` |
| `rwip_config.h` | `src/modules/rwip/api/rwip_config.h` |

## 5. Function Anchors

| Function | Observed location |
|---|---|
| `rwip_init(uint32_t error)` | `src/modules/rwip/src/rwip.c:721` |
| `rwip_driver_init(uint8_t init_type)` | `src/modules/rwip/src/rwip_driver.c:683` |
| `h4tl_init(uint8_t tl_itf, ...)` | `src/modules/h4tl/src/h4tl.c:1126` |
| `hci_cmd_received(uint16_t opcode, ...)` | `src/ip/hci/src/hci_tl.c:1574` |
| `rwip_eif_get(uint8_t idx)` | `src/plf/refip/src/arch/main/arch_main.c:481` |

## 6. H7 Result

PASS:

- Required vendor roots are present.
- Minimal runtime candidate source files are present.
- Core RWIP, H4TL, HCI, and platform function anchors were found.
- No vendor source files were copied into this repository.

BLOCKED:

- Vendor source/link approval is not established in this environment.
- No source import, object import, or runtime image link is allowed until the approval gate is explicitly closed.

PARTIAL:

- H7 proves asset presence and integration candidates only. It does not prove buildability, runtime initialization, HCI command consumption, or Linux RX.

## 7. Approved Next Work Without Vendor Copy

The following work can continue without violating the H7 gate:

- Keep building local sidecar skeleton and bridge contracts.
- Add adapter boundary headers that describe callbacks and ownership without including CEVA source.
- Prepare symbol inventory and build-plan documentation.
- Continue Linux host shim preparation that does not depend on linking CEVA runtime.

The following work remains blocked:

- Copying CEVA source into this repository.
- Committing CEVA source snippets.
- Linking a CEVA runtime object or binary.
- Claiming `rwip_init()` or real HCI Reset PASS.

## 8. Next Safe Action

Proceed to H8 as an adapter-boundary and symbol-inventory phase only. H8 must not link or vendor-copy until H7 approval is explicitly closed.
