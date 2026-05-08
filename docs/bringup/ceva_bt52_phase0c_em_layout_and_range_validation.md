# CEVA BT5.2 Phase 0C EM Layout And Range Validation

## 1. Goal

在 `Phase 0C-A` 的最小两地址 smoke 已经通过之后，这一阶段把目标收敛为两件事：

- 明确当前 EM debug window 的地址语义，避免把 CEVA 内部 word-address 和系统侧 byte-address 混在一起。
- 在板上把验证范围从 `0x65010000 / 0x65010004` 扩展成一组代表性偏移，给后续 CEVA EM 数据结构分配一个最小可用布局草案。

## 2. 已确认的地址语义

当前实现里，系统侧看到的 EM debug window 仍然是 byte-addressed：

- `0x65010000 .. 0x6501ffff`

但在 CEVA DM EM 控制器内部，AHB 路径进入 EM 之前，地址已经被右移 2 位：

```verilog
assign cpu_em_addr = {2'b00,businterface_em_addr_capt[`RW_DM_ADDRESS_WIDTH-1:2]};
```

这说明 wrapper 接到的 `em_addr` 已经是以 32-bit word 为单位的线性地址，而不是还需要再做一次 `>> 2` 的 byte 地址。

同时，CEVA 内部多个 EM 使用者也都按这个语义形成地址：

```verilog
btipt_em_addr <= {txonptr,2'b00};
btipt_em_addr <= {txoffptr,2'b00};
btipt_em_addr <= {rxonptr,2'b00};
btipt_em_addr <= {rxoffptr,2'b00};
btipt_em_addr <= {rxlengthptr,2'b00};
btipt_em_addr <= {rssiptr,2'b00};
btipt_em_addr <= {rxpkttypptr,2'b00};
btipt_em_addr <= {spiptr,2'b00};
```

以及：

```verilog
rp_em_addr <= {spiptr,2'b00};
rp_em_addr <= {spiptr,2'b00} + 16'h4;
```

因此当前 bringup 阶段可以稳定采用下面这条规则：

- 系统侧调试地址仍用 `0x6501xxxx` byte offset 表示。
- CEVA 内部逻辑记录的 pointer 是 word pointer，真正发到 EM 总线时通过 `{ptr,2'b00}` 形成 4-byte 对齐地址。
- wrapper 内部 BRAM 索引必须直接使用 `em_addr` 的低 `14` 位 word index，而不能再右移 2 位。

## 3. 最小布局草案

下面这份布局不是 CEVA vendor 最终功能语义表，而是当前 bringup 阶段已经有板级证据支撑、适合继续扩展的最小 EM 区块草案。

### 3.1 Contiguous Scratch / Alias Canary

- `0x65010000 .. 0x6501003f`
- 用途：验证相邻 word 独立性、连续地址线性映射、脚本/调试最小 scratch 区。

### 3.2 Low-Page Stride Probe

- `0x65010100 .. 0x6501013f`
- 用途：验证离开最底部 cacheline 后仍无低位 alias。

### 3.3 Mid-Range Page Probe

- `0x65010400 .. 0x6501043f`
- `0x65011000 .. 0x6501103f`
- 用途：验证更高地址位已真正进入 BRAM 索引，不只是底部页镜像。

### 3.4 High-Range Boundary Probe

- `0x65014000`
- `0x6501fffc`
- 用途：验证高位索引和 top-of-window 边界。

## 4. Range Sweep 脚本

新增板测脚本：

- `scripts/read_ceva_phase0c_em_range.sh`

默认覆盖的偏移为：

- `0x0000`
- `0x0004`
- `0x0008`
- `0x000c`
- `0x0010`
- `0x0020`
- `0x0040`
- `0x0100`
- `0x0400`
- `0x1000`
- `0x4000`
- `0xfffc`

每个偏移写入不同 32-bit pattern，然后在同一个 GDB 会话里对全部地址做写后重读。

这样可以同时抓住三类错误：

- 相邻 word alias
- 大步长地址位丢失
- 高边界回绕或镜像

## 5. 通过标准

对当前阶段，建议把下面两条同时作为 PASS 条件：

- `scripts/read_ceva_phase0c_em_window.sh` PASS
- `scripts/read_ceva_phase0c_em_range.sh` PASS

只有这两条都稳定通过，后续把 CEVA firmware / mailbox / sequence buffer 放进真实 EM 布局才是安全的。