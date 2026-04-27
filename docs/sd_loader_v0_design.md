# sd_loader_v0 设计文档 + Rocket BootROM 分析 (Phase C & D)

**版本**: v0  
**日期**: 2026-04-25  
**状态**: 设计文档（待实现）

---

## Part D: Rocket BootROM 分析

### D.1 BootROM 位置与大小

| 参数 | 值 |
|------|----|
| BootROM PA | 0x10000 |
| BootROM 大小上限 | **0x2000 (8 KB)** |
| hang 地址 (复位向量) | 0x10000 |
| _start 地址 | 由 `hang` 触发后跳转 |
| BSS/Stack 区域 | 0x08000000, 64KB (片上 scratchpad) |

链接脚本来源：`fpga/src/main/resources/zcu104/sdboot/linker/memory.lds`

```raw
bootrom_mem (rx) : ORIGIN = 0x10000, LENGTH = 0x2000
memory_mem (rwx) : ORIGIN = 0x08000000, LENGTH = 0x00010000
```

> **重要**：BSS 和 Stack 在片上 scratchpad (0x08000000)，不依赖 PS DDR 初始化。
> 这意味着 sd_loader_v0 可以在 DDR 就绪前运行，向 DDR 写入 fw_payload。

### D.2 当前 BootROM 行为 (baremetal.c)

```raw
上电 → _hang (0x10000) → mtvec=_start, mie=MSIP, WFI
     → MSIP 中断触发 → _start → hart0 reads BOOTADDR_REG (0x1000)
     → mepc=BOOTADDR_REG, mret → jump 到 sdboot (hang=0x10000)

sdboot main():
  1. UART 初始化 (SiFive UART @ 0x64000000, 115200bps)
  2. GPIO 初始化 (LED DS39 @ 0x64002000)
  3. DDR 测试 (0x80000000 + 0x7F00000 偏移，安全区域)
  4. 轮询 0x80001000 等待 XSDB/GDB 预加载 sentinel 非零
  5. 检测到 payload → 等待 3s → 检查 DTB magic → jump 0x80000000
```

### D.3 当前 BootROM 的问题

当前 BootROM 需要外部 GDB/XSDB 预加载 fw_payload，**无法独立自引导**。  
`sd_loader_v0` 要替换步骤 4-5，改为从 J100 SD 卡 PIO 读取。

### D.4 修改方案 (无 SPI，使用 SDHCI)

> ⚠️ **需要重新编译 BootROM 并重建 Vivado 比特流**。  
> 使用 `scripts/rebuild_bootrom.sh` 进行增量重建（~1小时），输出新 `.bit` 文件。  
> **必须在独立提交中完成，不得破坏 golden baseline。**

修改文件：`fpga/src/main/resources/zcu104/sdboot/baremetal.c`

修改内容：将 "XSDB 轮询" 逻辑替换为 "SDHCI PIO 读取" 逻辑（见 Part C）。

保留内容：
- UART 初始化和打印（调试用）
- DDR 测试（可选，验证 DDR 就绪）
- `jump_to_payload()` 跳转函数

---

## Part C: sd_loader_v0 设计

### C.0 SD 卡布局约定 (三分区方案)

sd_loader_v0 读取来源为 **p2 分区 (RAW rocketboot)**，内部偏移固定：

| 内容 | p2 内字节偏移 | p2 内扇区偏移 | 绝对 LBA |
|------|-------------|-------------|---------|
| manifest.bin | +0x00000000 | +0 | p2_start_lba + 0 |
| fw_payload | +0x00100000 | +2048 | p2_start_lba + 2048 |
| DTB | +0x03000000 | +98304 | p2_start_lba + 98304 |

偏移换算：
- `0x00100000 / 512 = 2048` 扇区
- `0x03000000 / 512 = 98304` 扇区

sd_loader_v0 在运行时通过以下方式确定 p2_start_lba：
1. 读取 GPT 分区表（LBA 2–33），查找 label = "ROCKETBOOT" 的分区起始 LBA
2. 或（简化方案）硬编码已知值（需在编译时通过 `Makefile` 宏设定）

**推荐使用 GPT 扫描**，避免烧录时的硬编码错误。

### C.1 硬件接口

| 参数 | 值 |
|------|----|
| SDHCI base (Rocket PA) | 0x60170000 |
| SDHCI → PS SDIO1 | 0xFF170000（通过 S_AXI_LPD） |
| SD 协议 | SDHCI 标准 v3.0，PIO 模式 |
| DMA | **永远禁止**（PS DMA 无法访问 Rocket DDR） |
| 编译器 | riscv64-unknown-elf-gcc, -march=rv64ima_zicsr_zifencei |
| 代码大小限制 | 8KB (BootROM 上限) |

### C.2 SDHCI PIO 关键寄存器

```c
// SDHCI 寄存器偏移（基址 0x60170000）
#define SDHCI_DMA_ADDRESS        0x00
#define SDHCI_BLOCK_SIZE         0x04  // [14:0]=block_size, [31:16]=block_count
#define SDHCI_ARGUMENT           0x08
#define SDHCI_TRANSFER_MODE      0x0C  // [15:8]=cmd, [7:0]=transfer mode
#define SDHCI_COMMAND            0x0E  // upper 16 bits of 0x0C
#define SDHCI_RESPONSE           0x10  // 4 x 32-bit
#define SDHCI_BUFFER             0x20  // Buffer Data Port (PIO 读写口)
#define SDHCI_PRESENT_STATE      0x24
#define SDHCI_HOST_CONTROL       0x28
#define SDHCI_POWER_CONTROL      0x29
#define SDHCI_CLOCK_CONTROL      0x2C
#define SDHCI_TIMEOUT_CONTROL    0x2E
#define SDHCI_SOFTWARE_RESET     0x2F
#define SDHCI_INT_STATUS         0x30
#define SDHCI_INT_ENABLE         0x34
#define SDHCI_SIGNAL_ENABLE      0x38
#define SDHCI_CAPABILITIES       0x40
#define SDHCI_MAX_CURRENT        0x48

// Present State bits
#define SDHCI_CMD_INHIBIT        (1 << 0)
#define SDHCI_DATA_INHIBIT       (1 << 1)
#define SDHCI_BUFFER_READ_ENABLE (1 << 11)

// Int Status bits
#define SDHCI_INT_CMD_COMPLETE   (1 << 0)
#define SDHCI_INT_XFER_COMPLETE  (1 << 1)
#define SDHCI_INT_BUF_READ_READY (1 << 5)
#define SDHCI_INT_ERROR          (1 << 15)

// Command register (offset 0x0E)
#define SDHCI_CMD_RESP_NONE      (0 << 0)
#define SDHCI_CMD_RESP_136       (1 << 0)
#define SDHCI_CMD_RESP_48        (2 << 0)
#define SDHCI_CMD_RESP_48_BUSY   (3 << 0)
#define SDHCI_CMD_DATA           (1 << 5)
#define SDHCI_CMD_INDEX(c)       ((c) << 8)

// Transfer Mode (offset 0x0C)
#define SDHCI_TRNS_READ          (1 << 4)
#define SDHCI_TRNS_MULTI         (1 << 5)
#define SDHCI_TRNS_BLKCNT_EN     (1 << 1)
#define SDHCI_TRNS_ACMD12        (1 << 2)
```

### C.3 卡初始化流程

假设 FSBL 已正确初始化 PS SDIO1 控制器（时钟、电源、MIO）。  
sd_loader_v0 只需重新初始化 SD 卡协议状态机：

```raw
CMD0  (GO_IDLE_STATE)    → 卡复位
CMD8  (SEND_IF_COND)     → 验证卡支持 2.7-3.6V (arg=0x1AA)
ACMD41 (SD_SEND_OP_COND) → 轮询直到 OCR[31]=1 (busy bit cleared)
                         → arg = 0x40FF8000 (HCS=1, 电压范围)
CMD2  (ALL_SEND_CID)     → 获取 CID (R2 响应)
CMD3  (SEND_RELATIVE_ADDR)→ 获取 RCA (R6 响应)
CMD7  (SELECT_CARD)      → 选中卡 (arg = RCA << 16)
CMD16 (SET_BLOCKLEN)     → 设置 block size = 512 (arg = 512)
                         → SDHC/SDXC 卡可省略（已固定512）
```

ACMD41 前需先发 CMD55 (APP_CMD, arg=RCA<<16)。

### C.4 读取流程

读取单扇区（CMD17）或多扇区（CMD18）：

```c
// 多扇区 PIO 读 (推荐)
// 1. 设置 Block Size=512, Block Count=n
// 2. 设置 Transfer Mode = READ | MULTI | BLKCNT_EN | ACMD12
// 3. 发送 CMD18 (READ_MULTIPLE_BLOCK), arg = start_lba (SDHC 卡)
// 4. 对每个扇区:
//    a. 轮询 INT_STATUS[5] (BUF_READ_READY)
//    b. 读 128 个 32-bit words from SDHCI_BUFFER
//    c. 清除 BUF_READ_READY 状态位
// 5. 等待 INT_STATUS[1] (XFER_COMPLETE)
// 6. 发送 CMD12 停止传输（如果没有 ACMD12 自动停止）
```

### C.5 sd_loader_v0 主流程 (伪代码)

```c
// p2 内固定扇区偏移
#define P2_FW_SECTOR_OFFSET   2048    // 0x00100000 / 512
#define P2_DTB_SECTOR_OFFSET  98304   // 0x03000000 / 512

int main(void) {
    uart_puts("[sdboot] sd_loader_v0 start\n");
    
    // 1. SDHCI 软件复位
    sdhci_reset(SDHCI_RESET_ALL);
    uart_puts("[sdboot] sdhci reset ok\n");
    
    // 2. SD 卡初始化
    if (sd_card_init() != 0) {
        uart_puts("[sdboot] FATAL: card init failed\n");
        goto hang;
    }
    uart_puts("[sdboot] card init ok\n");
    
    // 3. 扫描 GPT 分区表，找到 p2 (ROCKETBOOT) 起始 LBA
    uint64_t p2_start_lba = gpt_find_partition_by_label("ROCKETBOOT");
    if (p2_start_lba == 0) {
        uart_puts("[sdboot] FATAL: ROCKETBOOT partition not found\n");
        goto hang;
    }
    uart_puts("[sdboot] p2 found\n");
    
    // 4. 读取 Manifest (p2 首扇区 = p2_start_lba + 0)
    struct sd_manifest mf;
    if (sd_read_sectors(p2_start_lba, 1, &mf) != 0) goto hang;
    if (mf.magic != SD_MANIFEST_MAGIC) {
        uart_puts("[sdboot] FATAL: manifest magic mismatch\n");
        goto hang;
    }
    uart_puts("[sdboot] manifest ok\n");
    
    // 5. 读取 fw_payload → 0x80000000
    //    fw_lba = p2_start_lba + P2_FW_SECTOR_OFFSET (验证: mf.fw_lba == 此值)
    uart_puts("[sdboot] loading fw_payload...\n");
    uint32_t fw_sectors = (mf.fw_size + 511) / 512;
    if (sd_read_sectors(mf.fw_lba, fw_sectors,
                        (void *)(uintptr_t)mf.fw_load_addr) != 0) goto hang;
    uart_puts("[sdboot] fw ok\n");
    
    // 6. 验证 fw CRC32
    if (crc32_verify((void *)(uintptr_t)mf.fw_load_addr,
                     mf.fw_size, mf.fw_crc32) != 0) {
        uart_puts("[sdboot] FATAL: fw crc32 mismatch\n");
        goto hang;
    }
    uart_puts("[sdboot] fw crc32 ok\n");
    
    // 7. 读取 DTB → 0x84000000
    //    dtb_lba = p2_start_lba + P2_DTB_SECTOR_OFFSET (验证: mf.dtb_lba == 此值)
    uint32_t dtb_sectors = (mf.dtb_size + 511) / 512;
    if (sd_read_sectors(mf.dtb_lba, dtb_sectors,
                        (void *)(uintptr_t)mf.dtb_load_addr) != 0) goto hang;
    uart_puts("[sdboot] dtb ok\n");
    
    // 8. fence + 跳转
    __asm__ __volatile__("fence rw, rw" ::: "memory");
    __asm__ __volatile__("fence.i"      ::: "memory");
    // a0 = 0 (hart id), a1 = DTB PA (0x84000000)
    jump_to_payload(0, (uintptr_t)mf.dtb_load_addr);  // → 0x80000000
    
hang:
    while (1) { /* blink LED error */ }
}
```

### C.6 代码规模估算

| 模块 | 估计大小 |
|------|---------|
| head.S (入口) | ~100 B |
| uart_init/puts | ~400 B |
| sdhci_reset | ~200 B |
| sd_card_init (CMD0/8/ACMD41/2/3/7) | ~800 B |
| sd_read_sectors (PIO) | ~600 B |
| crc32_verify | ~300 B |
| manifest 处理 + main | ~400 B |
| **合计估计** | **~2.8 KB** |

8KB BootROM 上限有足够裕量。

### C.7 关键实现注意事项

#### C.7.1 SDHC vs SDSC 卡地址
- SDHC/SDXC 卡 (> 2GB)：CMD17/18 的 arg 直接是 LBA 地址
- SDSC 卡 (< 2GB)：arg 是字节地址 = LBA × 512  
- Fedora SD 卡通常 > 2GB，使用 SDHC，OCR[30]=HCS=1

```c
// 判断：ACMD41 响应 R3 中 OCR[30]=1 → SDHC
uint32_t is_sdhc = (ocr >> 30) & 1;
uint32_t addr = is_sdhc ? lba : (lba * 512);
```

#### C.7.2 SDHCI 时钟
FSBL 运行后，PS SDIO1 时钟已被 psu_init 配置。  
BootROM 可以直接使用当前时钟（不需要重新设置 Clock Control 寄存器）。  
如果需要，Clock Control (offset 0x2C) 可配置为低速 400kHz 初始化，  
然后在卡初始化后切换到 25MHz。

#### C.7.3 超时处理
所有 "轮询等待" 必须有超时计数器，避免死循环：
```c
#define SDHCI_TIMEOUT_LOOPS 1000000UL
// 在 50MHz CPU，1M loops ≈ 20ms
```

#### C.7.4 大文件读取进度
fw_payload 16.81MB = 34432 个扇区，在 25MHz SD 时钟下：
- 每扇区 512B，25MHz SDR，约 0.2ms/sector
- 总计约 **7 秒**
- BootROM 应每 1000 扇区打印一次进度点

#### C.7.5 SDHCI Present State 检查
发送命令前必须等待 CMD_INHIBIT 和 DATA_INHIBIT 清除：
```c
while (sdhci_reg32(SDHCI_PRESENT_STATE) & (SDHCI_CMD_INHIBIT | SDHCI_DATA_INHIBIT));
```

### C.8 实现文件

需要新增/修改的文件：

```raw
fpga/src/main/resources/zcu104/sdboot/
├── baremetal.c          ← 修改: 替换 XSDB 轮询为 sd_loader_v0_main()
├── sdhci.h              ← 新增: SDHCI 寄存器定义
├── sdhci.c              ← 新增: sdhci_reset(), sdhci_cmd(), sdhci_read_sector()
├── sdcard.c             ← 新增: sd_card_init(), sd_read_sectors()
├── crc32.c              ← 新增: crc32_verify()
└── sd_manifest.h        ← 新增: struct sd_manifest 定义
```

Makefile 更新：
```makefile
BOOTROM_SRCS := head.S baremetal.c sdhci.c sdcard.c crc32.c kprintf.c
```

### C.9 比特流重建

修改 `baremetal.c` 及新增文件后，需要：

```bash
# 1. 重新编译 BootROM
cd /root/chipyard
make -C fpga/src/main/resources/zcu104/sdboot PBUS_CLK=50 bin

# 2. 验证 BootROM 大小 <= 8192 字节
wc -c fpga/src/main/resources/zcu104/sdboot/build/sdboot.bin
# 期望: <= 8192

# 3. 重新生成 Chisel RTL (生成新的 TLROM.sv)
make -C /root/chipyard fpga/generated-src/.../gen-collateral/bootromClockSinkDomain.sv

# 4. 增量重建 Vivado 比特流 (~1小时)
bash /root/chipyard/fpga/scripts/rebuild_bootrom.sh
```

> ⚠️ **比特流重建必须在独立提交中进行，不得污染 golden baseline。**  
> 重建前备份现有 `.bit` 文件（`rebuild_bootrom.sh` 会自动备份）。

---

## Part D.5: BootROM 测试策略

### D.5.1 单元测试
在实际烧写前，可以用 XSDB 将 sd_loader_v0 程序加载到 scratchpad (0x08000000)  
并从该地址运行，测试 SDHCI init 和 sector 读取逻辑，无需重建比特流。

### D.5.2 集成测试顺序
1. XSDB 加载到 scratchpad，测试 SDHCI init 和 Manifest 读取
2. 验证 Manifest magic 和 CRC32
3. 测试完整 fw_payload 读取 (7s) 并 SHA256 校验
4. 测试完整引导链：从 SD 读取 → fw_payload → OpenSBI → Linux → Fedora

### D.5.3 回归测试
每次修改后必须能用 `run_fedora_v3fix_pio.sh` (XSDB preload 路径) 恢复到  
golden baseline，以确认 SDHCI PIO 驱动本身没有破坏现有引导链。

---

## Part D.6: 技术风险与缓解措施

| 风险 | 可能性 | 缓解措施 |
|------|--------|---------|
| BootROM > 8KB | 低 | 估计 2.8KB，有足够裕量 |
| SDHCI 时钟未初始化 | 中 | FSBL 已运行 psu_init；如需要，在 sdhci_reset 后重新配置 Clock Control |
| SDHC vs SDSC 地址错误 | 低 | 检查 ACMD41 响应的 HCS bit，动态选择字节/LBA 寻址 |
| CRC32 计算慢 | 低 | 仅验证 header/footer，或用 lookup table |
| DDR 写入后 I-cache 未刷新 | 高 | **必须在 jump 前执行 fence.i**（历史教训） |
| SDHCI 寄存器访问挂起 | 中 | 每次 MMIO 访问后加 fence；设置超时计数 |
| PS SDIO1 clock divider 设置问题 | 中 | 卡初始化用 <400kHz，传输用 25MHz；仅调 Clock Control[15:6] |
