# CEVA BT5.2 Phase 3B-G9A Vendor Runtime 最小资产清单

## 1. 结论

G9-A 的最小资产边界不是单个 `h4tl` parser，也不是当前 Linux 驱动里的 EM 写入逻辑。最小可执行资产必须覆盖 vendor runtime 的启动链、HCI 命令入口、事件出口、kernel/event/memory/timer runtime、platform transport adapter，以及 `rwip_driver_init()` 需要的寄存器访问头。

第一版允许把 BLE host/profile、应用层 profile、stock UART 驱动和低功耗优化先排除在默认构建之外，但不能排除 `ke`、`co`、HCI descriptor、EM map、IP register access 和 runtime scheduler。

## 2. 证据锚点

- Vendor SW root: `/mnt/e/桌面/CEVA_BT5.2/home/user007/project/CEVA_BT5.2/rw-btdm-blehost-sw-v11_0_3`
- Vendor HW root: `/mnt/e/桌面/CEVA_BT5.2/home/user007/project/CEVA_BT5.2/rw-dm-hw-v11_00_03`
- 审计目录: `logs/phase3b_g9_extended_20260512_215738`
- 入口证据: `20_entry_function_tree.txt`
- runtime service 证据: `21_runtime_services.txt`
- 寄存器访问证据: `23_register_access_refs.txt`
- 当前 payload 边界: `60_payload_boot_boundary.txt`

## 3. 必须资产

| 类别 | 最小资产 | 用途 |
|---|---|---|
| runtime entry | `src/modules/rwip/src/rwip.c`, `src/modules/rwip/api/rwip.h` | 提供 `rwip_init()`、`rwip_reset()`、`rwip_eif_api` 和 runtime 顶层生命周期。 |
| hardware driver | `src/modules/rwip/src/rwip_driver.c` | 提供 `rwip_driver_init()`、`rwip_isr()`、timer、SWINT、wake/sleep、AES ISR 入口。 |
| H4 transport | `src/modules/h4tl/src/h4tl.c`, `src/modules/h4tl/api/h4tl.h` | 提供 stock H4TL 输入状态机和 `h4tl_write()` 输出序列化能力；第一版可作为 sidecar 内部实现而不是 Linux 外部契约。 |
| HCI core | `src/ip/hci/src/hci.c`, `src/ip/hci/src/hci_tl.c`, `src/ip/hci/src/hci_msg.c`, `src/ip/hci/api/hci.h` | 提供 `hci_cmd_received()`、`hci_send_2_host()`、HCI descriptor lookup、Command Complete/Event routing。 |
| kernel runtime | `src/ip/ke/**` 中的 `ke_event`, `ke_mem`, `ke_msg`, `ke_task`, `ke_timer` | vendor scheduler、message allocation、event dispatch 和 timer 依赖，不能用 Linux HCI callback 替代。 |
| common runtime | `src/ip/co/**` 中的 `co_list`, `co_utils`, `co_endian`, `co_error`, `co_time`, `co_djob` | list、endianness、error、time、deferred job 等基础设施。 |
| scheduler | `src/ip/sch/**` | SWINT 后的 immediate scheduling 依赖 `sch_arb_sw_isr()`，真实 runtime 必须带。 |
| EM/register map | `em_map.h`, `reg_access.h`, `reg_ipcore.h`, `reg_ipcore_bts.h`, `reg_em_*` | `rwip_driver_init()`、ISR、descriptor access、timer access 的硬件寄存器/EM 视图。 |
| platform glue | `src/plf/refip/src/arch/main/arch_main.c` 或 `src/plf/bluegrip/src/arch/main/arch_main.c` 的最小等价层 | 证明 stock runtime 通过 `rwip_eif_get(0)` 提供 `uart_api`；sidecar 需要替换为 bridge eif。 |
| interrupt/arch | platform `arch.h`, global interrupt macros, WFI/timer hooks | `GLOBAL_INT_DISABLE`、`GLOBAL_INT_RESTORE`、sleep/timer/ISR ownership 所需。 |
| build config | `rwip_config.h`、platform config、feature macro 集 | 决定 `BLE_EMB_PRESENT`、`BT_EMB_PRESENT`、`HCI_TL_SUPPORT`、`H4TL_SUPPORT`、host/profile 裁剪。 |

## 4. 入口函数依赖回答

### 4.1 `rwip_init()` 依赖哪些文件

`rwip_init(uint32_t error)` 的最小依赖来自 `rwip.c` 调用链：`ke_init()`、多段 `ke_mem_init()`、可选 `dbg_init()`、`rf_init()`、`ecc_init()`、`h4tl_init()`、`hci_init()`、可选 `ahi_init()`、`rwble_hl_init()`、`rwbt_init()`、`rwble_init()`、`rwip_driver_init()`、`co_djob_init()`、`co_time_init()`、可选 `co_buf_init()`、可选 `appm_init()`，最后进入 `rwip_reset()`。

因此必须带：

- `rwip.c` / `rwip.h`
- `rwip_config.h`
- `ke_*` runtime
- `co_*` runtime
- `h4tl` 或替代 eif adapter
- `hci` / `hci_tl` / `hci_msg`
- `rwbt`、`rwble` 中由配置打开的 controller 子集
- `rwip_driver.c` 和 register access headers
- platform init、interrupt、timer、assert、NVDS 参数提供层

### 4.2 `h4tl_init()` 依赖哪些文件

`h4tl_init(uint8_t tl_itf, const struct rwip_eif_api *eif)` 存储 `eif`，调用 `flow_on()`，注册 `KE_EVENT_H4TL_TX`、`KE_EVENT_H4TL_CMD_HDR_RX`、`KE_EVENT_H4TL_CMD_PLD_RX` 等事件回调，然后调用 `h4tl_read_start()` 通过 `eif->read()` 开始收包。

必须带：

- `h4tl.c` / `h4tl.h`
- `rwip.h` 中的 `struct rwip_eif_api`
- `ke_event` callback 机制
- `ke_malloc` / `ke_free`
- `hci.h` / `hci_tl.c` 中的 `hci_cmd_received()`、`hci_cmd_get_max_param_size()`
- `rwip_prevent_sleep_set()` / `rwip_prevent_sleep_clear()`
- transport adapter 提供 `read`、`write`、`flow_on`、`flow_off`

### 4.3 `hci_cmd_received()` 依赖哪些文件

`hci_cmd_received(uint16_t opcode, uint8_t length, uint8_t *payload)` 定义在 `hci_tl.c`，依赖 `hci_look_for_cmd_desc()`、`hci_tl_env.nb_h2c_cmd_pkts`、`ke_msg` 分配和 task routing。它不是裸函数入口，必须带 HCI descriptor 表和 vendor task/message runtime。

必须带：

- `hci_tl.c`
- `hci_msg.c` 中的 descriptor lookup 和 descriptor tables
- `hci.h` / `hci_int.h`
- `ke_msg`, `ke_task`, `ke_event`
- `co_list`, `co_utils`, `co_endian`
- controller task 目标：至少 `TASK_LLM`、`TASK_LM`、`TASK_DBG` 中配置实际打开的子集

### 4.4 `hci_send_2_host()` 依赖哪些文件

`hci_send_2_host(void *param)` 定义在 `hci.c`。它先用 `ke_param2msg(param)` 找回 message，再根据 event mask/filter 判断是否丢弃；如果不是 embedded host 内部消费，则通过 `hci_tl_send(msg)` 走 transport layer 输出。

必须带：

- `hci.c`
- `hci_tl.c` 中的 `hci_tl_send()`、queue/env
- HCI event descriptor tables
- `ke_msg` / `ke_task`
- H4TL 或 sidecar egress serializer
- bridge egress adapter，把 vendor event 转成 EM[96] event window

### 4.5 `rwip_driver_init()` 依赖哪些寄存器访问头

`rwip_driver_init(uint8_t init_type)` 会执行 IP core reset、interrupt enable、timer/sleep/NVDS 初始化。最小寄存器访问依赖：

- `reg_ipcore.h`: `ip_rwdmcntl_*`, `ip_intcntl1_*`, `ip_intack1_*`, `ip_intstat1_*`, timer target, sleep/wakeup, AES 控制等。
- `reg_ipcore_bts.h`: BLE ISO/BTS 相关寄存器，若 BLE ISO 配置关闭可裁剪。
- `reg_access.h`: MMIO/EM 访问 primitive。
- `em_map.h`: EM memory layout。
- `reg_em_*`: BT/BLE descriptor、RX/TX buffer、ACL/ISO buffer 配置实际打开的子集。

## 5. `ke` / `co` 最小子集

| 子集 | 是否必须 | 原因 |
|---|---|---|
| `ke_event` | 必须 | H4TL RX/TX 事件、AES done、scheduler event 都依赖。 |
| `ke_mem` | 必须 | H4TL payload buffer、HCI message allocation、runtime heap。 |
| `ke_msg` | 必须 | HCI command/event 以 message 形式在 task 间路由。 |
| `ke_task` | 必须 | `hci_cmd_received()` 根据 descriptor 发送到 controller task。 |
| `ke_timer` | 必须 | controller scheduler、LLM/LM timer、common timer。 |
| `co_list` | 必须 | HCI TL queue、scheduler queue、message queue。 |
| `co_time` | 必须 | `rwip_init()` 初始化，scheduler/timer 需要。 |
| `co_djob` | 必须 | deferred job runtime。 |
| `co_buf` | 配置相关 | 如果配置启用 BLE host/GAF/ISO buffer，需要；纯 controller first path 可先关闭。 |
| `co_endian` / `co_utils` / `co_error` | 必须 | HCI packet serialization、error code、utility。 |

## 6. 可选资产

- `ahi` / Application Host Interface：除非管理/diagnostic path 强依赖，第一版不作为 Reset/RLV 路径必要资产。
- `tracer` / debug trace：可保留为调试选项，默认 runtime first proof 不依赖。
- `rwble_hl` / BLE host higher layer：如果 sidecar 只做 controller-facing HCI，不应把 full BLE host/profile 带入第一版。
- `appm` / demo app：第一版 sidecar 不做 demo application owner。
- stock UART driver：可以作为参考，但生产 bridge eif 应替换 `uart_api`，不把 UART 作为 Linux 边界。
- low-power/deep-sleep 平台代码：第一版可固定为 active/no-deep-sleep，直到 Reset/RLV real path 成立。

## 7. 明确不需要资产

- Linux BlueZ scan/pair/connect 相关 userspace 流程。
- 当前 synthetic responder 扩展代码。
- BLE profile、GATT sample app、GAF/audio profile、mesh/profile test app。
- FPGA bitstream、Vivado project、RTL filelist 变更。
- 当前 vendor hardware tree 下的 FPGA image binary、sdcard image、`fw.bin` 产物。
- Linux userspace fake controller helper。

## 8. 未找到但可能需要资产

Open Blocker 1: vendor SW 的正式 build configuration 入口尚未冻结。需要确认实际目标是 `refip`、`bluegrip` 还是 vendor 已交付的 BTDM controller profile。

Open Blocker 2: linker script、startup assembly、vector table 和 exact memory map 尚未冻结。需要 vendor 或现有固件提供可合法复用的 sidecar startup 模板。

Open Blocker 3: `rwip_param.get()` / NVDS 参数来源尚未冻结。第一版可以用固定参数 stub，但真实 controller 需要合法参数表。

Open Blocker 4: CEVA 内部 runtime context 是否存在尚未证明。如果 vendor 架构有内部控制器 CPU/固件入口，优先级高于 Rocket-side sidecar。

Open Blocker 5: vendor license/redistribution 规则需要明确允许把 runtime source 或 blob 纳入本 repo 或构建环境。

## 9. Legal/vendor approval 风险

该路线依赖 vendor runtime 资产，不允许把外部 vendor source 直接拷入 repo，除非 license、NDA、redistribution 和交付边界都已获批。当前文档只记录资产清单和接口，不提交 vendor source，不提交 vendor binary。

最小审批项：

- 是否允许在本 workspace 构建 vendor runtime。
- 是否允许把 sidecar binary 打入 payload 或 initramfs。
- 是否允许提交 build glue，但不提交 vendor source。
- 是否允许引用外部 vendor path 作为本地 build input。
- 是否存在 vendor 已编译 controller firmware blob 可直接使用。

## 10. PASS / FAIL / STOP

PASS 条件：

- 已冻结 vendor runtime 最小资产列表。
- 已冻结必须宏和配置方向：controller runtime first、Linux host shim、EM/SWINT bridge v0。
- 已明确哪些 BLE host/profile 不纳入第一版。
- 已明确 legal/vendor approval owner 和 Open Blockers。

FAIL 条件：

- 仍把 `h4tl.c` 单独当作完整 consumer。
- 仍把当前 Linux EM/SWINT 发布路径当作真实 runtime。
- 资产清单无法覆盖 `rwip_init()` 到 `rwip_driver_init()` 的初始化链。

STOP 条件：

- vendor runtime source/blob 无法合法使用。
- 无法确认构建配置和寄存器访问头的来源。
- 必须资产要求直接改 RTL 或 Vivado 才能开始软件 proof。
