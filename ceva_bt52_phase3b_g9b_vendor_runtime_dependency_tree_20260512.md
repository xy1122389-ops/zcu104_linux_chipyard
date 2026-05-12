# CEVA BT5.2 Phase 3B-G9B Vendor Runtime 依赖树与编译模型

## 1. 结论

Vendor runtime 能在 baremetal sidecar 中编译的前提是：保留 vendor `ke/co` runtime、HCI descriptor、controller task、register access 和 platform interrupt/timer glue；只替换 platform transport 和少量 board service。它不适合直接塞进 Linux kernel，因为它自带 scheduler、heap、message queue、interrupt ownership 和 controller reset 时序。

## 2. 从 `rwip_init()` 展开的函数调用树

```text
rwip_init(error)
  -> ke_init()
  -> ke_mem_init(...) for kernel/runtime heaps
  -> optional dbg_init()
  -> rf_init() / ecc_init() if enabled
  -> h4tl_init(tl_itf=0, rwip_eif_get(0)) if H4TL_SUPPORT
       -> store struct rwip_eif_api
       -> eif->flow_on()
       -> ke_event_callback_set(KE_EVENT_H4TL_TX)
       -> ke_event_callback_set(KE_EVENT_H4TL_CMD_HDR_RX)
       -> ke_event_callback_set(KE_EVENT_H4TL_CMD_PLD_RX)
       -> h4tl_read_start()
            -> eif->read(..., h4tl_rx_done, env)
  -> hci_init(init_type)
       -> hci_tl_init(init_type)
       -> reset HCI TL queues and command credit
  -> optional ahi_init()
  -> optional rwble_hl_init()
  -> rwbt_init(init_type) if BT_EMB_PRESENT
  -> rwble_init(init_type) if BLE_EMB_PRESENT
  -> rwip_driver_init(init_type)
       -> ke_event_callback_set(KE_EVENT_AES_END)
       -> rwip_prevent_sleep_set(RW_PLF_DEEP_SLEEP_DISABLED)
       -> ip_rwdmcntl_master_soft_rst_setf(1)
       -> wait for reset complete
       -> ip_intcntl1_set(FIFO | CRYPT | SW | SLP masks)
       -> configure diag/sleep/NVDS-dependent values
  -> co_djob_init()
  -> co_time_init()
  -> optional co_buf_init()
  -> optional appm_init()
  -> rwip_reset() for reset modes
```

这棵树说明入口不是一个 callback，而是完整 controller runtime bootstrap。第一版 sidecar skeleton 可以先只写 marker；一旦接 vendor runtime，就必须按这棵树满足服务依赖。

## 3. `h4tl_init()` 怎么接收输入

`h4tl_init(uint8_t tl_itf, const struct rwip_eif_api *eif)` 通过 `struct rwip_eif_api` 接收平台 transport。stock `arch_main.c` 中 `rwip_eif_get(0)` 返回 `uart_api`，包含 `uart_read`、`uart_write`、`uart_flow_on`、`uart_flow_off`。

Sidecar v0 不应该把 UART 作为系统边界。应新增 bridge eif：

```text
bridge_read(buf, len, callback, env)
  从 EM[64..] command window 或 sidecar ingress queue 取数据

bridge_write(buf, len, callback)
  把 HCI event/ACL bytes 写入 EM[96..] event window

bridge_flow_on()
  标记 SIDECAR_INGRESS_READY

bridge_flow_off()
  标记 sidecar 暂停接收
```

第一版推荐直接把 EM command 解析为 `opcode + length + payload` 后调用 `hci_cmd_received()`。只有当 direct ingress 与 vendor internal state 不兼容时，才保留 H4TL 内部路径，并在 sidecar 内合成 H4 command packet 给 `h4tl`。

## 4. `hci_cmd_received()` 输入参数

函数签名：

```c
void hci_cmd_received(uint16_t opcode, uint8_t length, uint8_t *payload);
```

输入含义：

| 参数 | 含义 | Reset 示例 |
|---|---|---|
| `opcode` | HCI opcode，小端 command header 中的 OGF/OCF 合成值 | `0x0C03` |
| `length` | command parameters 长度 | `0` |
| `payload` | 参数 buffer，长度为 `length`；无参数时为 `NULL` | `NULL` |

内部处理：

- 通过 `hci_look_for_cmd_desc(opcode)` 找 descriptor。
- 标记 `hci_ext_host = true`，表示外部 host 正在通过 HCI TL 使用 embedded controller。
- 消耗 HCI command credit。
- 根据 descriptor 的 destination field 路由到 `TASK_LLM`、`TASK_LM`、`TASK_DBG` 等 lower-layer task。
- 用 `ke_msg` 把 command 送入 vendor task runtime。

## 5. `hci_send_2_host()` 输出参数

函数签名：

```c
void hci_send_2_host(void *param);
```

输出含义：

- `param` 是 vendor `ke_msg` 参数区指针。
- `hci_send_2_host()` 调用 `ke_param2msg(param)` 找回 message header。
- 如果 event mask/filter 不允许，会释放 message。
- 如果走外部 host TL，会调用 `hci_tl_send(msg)`。
- HCI TL 再通过 H4TL 或 sidecar egress serializer 输出 HCI event/ACL bytes。

Sidecar egress adapter 的代码边界应放在 `hci_tl_send()` 之后或 H4TL `h4tl_write()` 的 eif `write` 回调处。这样可以尽量保留 vendor event 构造逻辑，不在 Linux driver 内重新造 event。

## 6. Runtime service 表

| service | 使用者 | sidecar 编译要求 | 是否能 stub |
|---|---|---|---|
| `ke_init` | `rwip_init` | 必须真实初始化 kernel runtime | 不能空 stub |
| `ke_mem_init` | `rwip_init`, H4TL, HCI | 必须提供 heap/allocator | 不能空 stub |
| `ke_event_callback_set` | H4TL, AES, scheduler | 必须注册和调度事件 | 不能空 stub |
| `ke_msg` | HCI command/event path | 必须支持 alloc/send/free 和 task id | 不能空 stub |
| `ke_task` | HCI routing | 必须有 controller task dispatch | 不能空 stub |
| `ke_timer` | scheduler/controller | 必须有 tick source 或等价 timer | 不能空 stub |
| `co_list` | HCI TL queue, scheduler | 必须提供真实 list primitives | 不能空 stub |
| `co_time` | `rwip_init`, scheduler | 第一版可用固定 active tick，但真实 path 要运行 | 可窄 stub 到 monotonic source |
| `co_djob` | deferred job | 必须初始化，是否运行取决于配置 | 可有限实现 |
| `GLOBAL_INT_DISABLE/RESTORE` | driver/ISR/timer | baremetal 需要真实 critical section | 不能空 stub |
| `ASSERT/ASSERT_ERR/ASSERT_INFO` | 全局 | 可映射到 marker + halt/log | 可 stub 到 fail marker |
| `memcpy/memset/memcmp` | 全局 | 需要 libc 或 freestanding implementation | 可用 freestanding libc |
| `rwip_param.get` / NVDS | driver config | 第一版可固定返回 known defaults | 可有限 stub |
| `uart_api` | stock transport | sidecar bridge 替代 | 可替换，不保留 UART |
| `led_set/led_reset/WFI` | platform sleep loop | first proof 可禁 deep sleep | 可窄 stub |

## 7. 需要 stub 的接口

第一版 sidecar skeleton 或 runtime bring-up 可以 stub 的部分：

- `uart_read/write/flow_on/flow_off`: 替换为 EM/SWINT bridge eif。
- `printf`/trace/log: 替换为 marker 或 ring buffer。
- `ASSERT_*`: 写 fail marker，然后停在可观察状态。
- `rwip_param.get`: 先返回固定 sleep disabled、diag disabled、public address 参数；真实蓝牙地址后续由 vendor 参数表补齐。
- `led_set/led_reset`: 空操作或 marker。
- low-power WFI/deep sleep: 第一版固定 active，避免引入 wakeup 变量。
- host/profile app init: 通过 config 关闭，不进入 stub。

## 8. 不能 stub 的接口

以下接口如果空 stub，会得到假成功或破坏 runtime：

- `ke_mem` allocator。
- `ke_msg` message path。
- `ke_event` event dispatch。
- `ke_task` task routing。
- HCI descriptor lookup 和 command table。
- `hci_tl_env` command credit/queue。
- `rwip_driver_init()` 中的 IP reset 和 interrupt mask programming。
- `rwip_isr()` / `rwip_sw_int_handler()` / `sch_arb_sw_isr()`。
- EM/register access primitives。
- Sidecar ingress/egress bridge ownership flags。

## 9. Baremetal sidecar 可行性判断

Baremetal sidecar 是可行的，但不是零依赖移植。可行性来自：

- vendor runtime 已经以 platform abstraction 方式组织，`rwip_eif_get()` 显示 transport 可替换。
- `h4tl_init()` 接收 `rwip_eif_api`，bridge transport 可以复用这个 seam。
- `hci_cmd_received()` 和 `hci_send_2_host()` 提供清晰 ingress/egress 语义。
- `rwip_driver_init()` 直接拥有 CEVA IP reset 和 interrupt enable，适合放在 firmware context，而不适合拆进 Linux HCI driver。

可行性前提：

- sidecar 有独立执行流和 interrupt/timer ownership。
- sidecar memory 不被 Linux 覆盖。
- sidecar 能访问 CEVA DM/EM MMIO 区。
- Linux 只通过 bridge contract 与 sidecar 通信。

## 10. Linux kernel 不适合的原因

Linux kernel 路线被否决，原因不是缺一个函数包装，而是模型冲突：

- vendor runtime 自带 scheduler、task、message、heap 和 timer。
- `rwip_driver_init()` 期待拥有 controller reset 和 interrupt mask 时序。
- HCI TL 的 command credit 和 queue 不等价于 Linux HCI core 的 skb lifecycle。
- `GLOBAL_INT_DISABLE/RESTORE`、WFI、sleep prevention 与 Linux kernel preemption/IRQ model 冲突。
- 把所有依赖塞进 `ceva_bt52.c` 会把薄 host shim 变成 vendor OS port，diff 面失控。

## 11. PASS / FAIL / STOP

PASS 条件：

- 调用树、runtime service、stub/不可 stub 清单已冻结。
- 明确第一版 direct ingress 和可选 H4TL internal path。
- 明确 baremetal sidecar 可行但需独立执行流。

FAIL 条件：

- 把 `hci_cmd_received()` 当作无需 `ke_msg/ke_task` 的普通函数。
- 把 `hci_send_2_host()` 当作直接输出 bytes 的函数。
- 空 stub `ke_event/ke_mem/ke_msg` 仍声称真实 path。

STOP 条件：

- 无独立执行流。
- 无合法 runtime assets。
- 只能通过 Linux kernel 巨型移植满足依赖。
