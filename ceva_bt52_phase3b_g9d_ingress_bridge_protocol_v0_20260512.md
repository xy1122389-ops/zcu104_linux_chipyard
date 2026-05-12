# CEVA BT5.2 Phase 3B-G9D Bridge Ingress Protocol v0

## 1. 结论

Ingress v0 继续使用当前 EM command window 与 SWINT doorbell，但把它正式定义为 Linux host shim 到 sidecar 的协议。Linux 外部边界不携带 H4 type byte；sidecar 看到的是 HCI command header/payload，并优先直接调用 `hci_cmd_received(opcode, parlen, payload)`。H4TL 只作为 sidecar 内部备选路径。

## 2. 必须回答

1. 是否继续用 EM[64] command words：是，v0 保留 EM[64..] 作为 command payload window。
2. EM[72] ready flag 是否保留：是，v0 保留为 command-ready flag。
3. SWINT doorbell 是否保留：是，v0 保留 DM SWINT request 作为 sidecar doorbell。
4. H4 type byte 是否保留：Linux-to-sidecar v0 不保留 H4 byte；如使用 H4TL internal path，sidecar adapter 在内部合成 `0x01` HCI command packet type。
5. sidecar 看到的是完整 H4 packet 还是 HCI command payload：v0 看到 HCI command header/payload，即 opcode、parameter length、payload。
6. ownership 谁清 flag：Linux 写 payload/length/seq/ready 并拉 SWINT；sidecar 读完并复制到私有 buffer 后清 `cmd_ready`。
7. 如果 sidecar 忙，Linux 如何重试：sidecar 写 `cmd_status=BUSY` 并保持或清 `cmd_ready`；Linux 只在 `cmd_ready==0` 且 `cmd_status!=BUSY` 时发布下一条，超时后重试同一 seq。
8. 如何标记 command consumed：sidecar 清 `cmd_ready`，写 `cmd_status=CONSUMED`，递增 `cmd_consumed_seq`，并写 `SIDECAR_CMD_CONSUMED` marker。

## 3. v0 byte layout

```text
EM[64..71]  command payload bytes, little-endian packed words
EM[72]      cmd_ready
EM[73]      reserved for egress event_ready, not used by ingress
EM[74]      cmd_len bytes
EM[75]      cmd_seq
EM[76]      cmd_status
EM[77]      cmd_consumed_seq
EM[78..79]  debug scratch / last opcode / last parameter length
```

Reset command example, payload excludes H4 type:

```text
cmd_len = 3
EM[64] bytes = 03 0C 00
opcode = 0x0C03
parlen = 0
payload = NULL
```

Read Local Version command example:

```text
cmd_len = 3
EM[64] bytes = 01 10 00
opcode = 0x1001
parlen = 0
payload = NULL
```

## 4. 状态值

| name | value | writer | meaning |
|---|---:|---|---|
| `CMD_IDLE` | `0x00000000` | sidecar | command slot empty |
| `CMD_READY` | `0x00000001` | Linux | payload/len/seq valid |
| `CMD_BUSY` | `0x00000002` | sidecar | sidecar cannot accept a new command |
| `CMD_CONSUMED` | `0x00000003` | sidecar | command copied and sent to vendor ingress |
| `CMD_ERROR` | `0xE0000001` | sidecar | malformed command or unsupported length |

## 5. 字段表

| name | address/offset | owner | writer | reader | reset value | valid value | clear rule | debug marker |
|---|---|---|---|---|---:|---|---|---|
| `cmd_payload` | EM word 64..71 | Linux until ready, sidecar after copy | Linux | sidecar | zero | HCI command bytes without H4 type | sidecar may zero after copy in debug builds | `SIDECAR_RX_CMD_0C03` for Reset |
| `cmd_ready` | EM word 72 | shared protocol | Linux sets, sidecar clears | sidecar, Linux retry path | `0` | `1` means valid command | sidecar clears after copying command to private buffer | `SIDECAR_CMD_CONSUMED` |
| `event_ready` | EM word 73 | egress only | sidecar | Linux | `0` | not used by ingress | not touched by ingress | none |
| `cmd_len` | EM word 74 | Linux | Linux | sidecar | `0` | `3..32` for v0 | sidecar clears with `cmd_ready` | `SIDECAR_RX_CMD_0C03` records length |
| `cmd_seq` | EM word 75 | Linux | Linux | sidecar | `0` | monotonically increasing nonzero value | Linux increments on new command | `SIDECAR_CMD_CONSUMED` records seq |
| `cmd_status` | EM word 76 | sidecar | sidecar | Linux/capture | `0` | idle/busy/consumed/error | Linux treats consumed as send complete, sidecar resets before next ready | `SIDECAR_CMD_CONSUMED` |
| `cmd_consumed_seq` | EM word 77 | sidecar | sidecar | Linux/capture | `0` | last consumed seq | overwritten per command | `SIDECAR_CMD_CONSUMED` |
| `last_opcode` | EM word 78 low 16 bits | sidecar debug | sidecar | capture | `0` | last parsed opcode | overwritten per command | `SIDECAR_RX_CMD_0C03` |
| `last_parlen` | EM word 78 high 8 bits | sidecar debug | sidecar | capture | `0` | last parsed parameter length | overwritten per command | `SIDECAR_RX_CMD_0C03` |
| `swint_doorbell` | DM SWINT request register | doorbell | Linux | sidecar ISR/poll | hardware reset | write pulse/request | hardware or sidecar ISR ack | `SIDECAR_INGRESS_READY` |

## 6. Linux publish sequence

```text
wait cmd_ready == 0
write cmd_payload bytes to EM[64..]
write cmd_len to EM[74]
write cmd_seq to EM[75]
write cmd_status = 0 to EM[76]
memory barrier
write cmd_ready = 1 to EM[72]
write DM_SWINT_REQ
```

Linux must not write a second command while `cmd_ready != 0` unless the retry policy explicitly observes timeout and sidecar is reset.

## 7. Sidecar consume sequence

```text
on SWINT or poll tick:
  if cmd_ready != 1:
    return
  read cmd_len
  validate 3 <= cmd_len <= 32
  copy EM[64..] to sidecar private command buffer
  parse opcode = buf[0] | (buf[1] << 8)
  parse parlen = buf[2]
  validate cmd_len == 3 + parlen
  write last_opcode / last_parlen
  if opcode == 0x0C03:
    write SIDECAR_RX_CMD_0C03
  clear cmd_ready
  write cmd_status = CMD_CONSUMED
  write cmd_consumed_seq = cmd_seq
  call hci_cmd_received(opcode, parlen, parlen ? &buf[3] : NULL)
```

## 8. Busy/retry rule

Sidecar busy means it cannot copy command into private buffer. It must not partially consume payload.

Rule:

- If busy before copy: sidecar writes `CMD_BUSY`, leaves `cmd_ready=1`, and does not write consumed marker.
- Linux waits a bounded interval, then re-rings SWINT with the same seq.
- If timeout repeats, Linux records ingress timeout and does not synthesize success.
- If sidecar copied payload, it owns completion and must clear `cmd_ready`.

## 9. PASS / FAIL / STOP

PASS 条件：

- Reset opcode `0x0C03` appears in `last_opcode` and `SIDECAR_RX_CMD_0C03` marker。
- `cmd_ready` is cleared by sidecar, not by Linux。
- `cmd_consumed_seq == cmd_seq`。
- No synthetic responder contributes to pass result。

FAIL 条件：

- Linux writes EM[64] and EM[72] but sidecar never observes seq。
- Sidecar sees SWINT but `cmd_len` or payload parse invalid。
- Linux clears ready before sidecar copies command。

STOP 条件：

- Protocol requires RTL EM layout changes before skeleton proof。
- The only ingress route requires moving full vendor runtime into Linux kernel。
- EM[64..79] collides with vendor internal EM ownership in a way that cannot be isolated by bridge adapter。
