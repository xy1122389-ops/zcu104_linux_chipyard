# SD 卡布局设计 — ZCU104 PL Rocket J100 自引导 (三分区方案)

**设计版本**: v1  
**日期**: 2026-04-25  
**方案**: ZCU104 自定义稳定三分区方案 (p1/p2/p3)

---

## 1. 目标

ZCU104 上电后，无需外部 GDB/XSDB 介入，Rocket BootROM 中的 sd_loader_v0 自动从  
J100 SD 卡 p2 (RAW rocketboot 分区) 读取 fw_payload 和 DTB，完成 Linux 引导。

---

## 2. 硬件路径

```raw
PS BootROM (ARM)
    → 读 p1 FAT32 → BOOT.BIN (FSBL + bitstream)
    → FSBL 执行 psu_init → 加载 bitstream → PL 上电
    → bitstream 内含 Rocket BootROM (sd_loader_v0)

Rocket BootROM / sd_loader_v0 (PA 0x10000)
    → SDHCI PIO (Rocket PA 0x60170000 → PS SDIO1 0xFF170000)
    → 读 p2 RAW → manifest.bin + fw_payload.bin.v3patched + DTB
    → DDR (Rocket PA 0x80000000)
    → OpenSBI fw_payload → Linux 6.6.0 → Fedora rootfs (p3 btrfs)
```

---

## 3. 三分区布局

### 3.1 分区表 (GPT)

| 分区 | 类型     | 大小  | Label      | 内容                              |
|------|----------|-------|------------|-----------------------------------|
| p1   | FAT32    | 256MB | BOOT       | BOOT.BIN (FSBL + bitstream)       |
| p2   | RAW      | 256MB | ROCKETBOOT | manifest.bin + fw_payload + DTB   |
| p3   | BTRFS    | 剩余  | fedora     | Fedora rootfs (subvol=root)       |

> p2 **不创建文件系统**，Rocket sd_loader_v0 直接按扇区偏移读取。  
> p3 是 Linux 挂载点 `/dev/mmcblk0p3`，mount 参数 `btrfs,subvol=root`，保持不变。

### 3.2 p2 内部 RAW 布局 (固定偏移)

```raw
p2 内偏移          扇区数  字节偏移       内容
────────────────────────────────────────────────────────
+0x00000000        1       0              manifest.bin (512 字节, magic SDR0)
+0x00000200        ~       512            [保留/补齐到 1MB]
+0x00100000        34432   2048 扇区      fw_payload.bin.v3patched (16.82 MB)
+0x03100000        10      98304+34432    [fw 末尾后保留]
+0x03000000        10      98304 扇区     外部 DTB (chipyard-zcu104-linux-slip.dtb)
```

**绝对 LBA 计算**（p2_start_lba 由 gdisk/sgdisk 给出，通常 ~524288 对应 256MB 对齐）：

```raw
manifest_lba  = p2_start_lba + 0
fw_lba        = p2_start_lba + 2048      (0x00100000 / 512)
dtb_lba       = p2_start_lba + 98304     (0x03000000 / 512)
```

### 3.3 p2 大小验证

| 内容           | 大小 (字节) | 扇区数  | p2 内扇区偏移 |
|----------------|-------------|---------|--------------|
| manifest.bin   | 512         | 1       | 0            |
| fw_payload     | 17,628,680  | 34,432  | 2048         |
| fw_payload 末  | —           | —       | 36,480       |
| DTB            | ~5,120      | 10      | 98,304       |
| DTB 末         | —           | —       | 98,314       |
| **p2 最小需要** | **~50 MB** | **98,314** | — |

256 MB p2 分区 = 524,288 扇区，远大于 98,314，有充足裕量。

---

## 4. Manifest 格式 (p2 首扇区, 512 字节)

```c
struct sd_manifest {
    uint32_t magic;         // 0x53445230 = "SDR0"
    uint32_t version;       // 0x00000001
    uint64_t fw_lba;        // = p2_start_lba + 2048
    uint64_t fw_size;       // 17628680 (字节)
    uint64_t fw_load_addr;  // 0x80000000
    uint64_t dtb_lba;       // = p2_start_lba + 98304
    uint64_t dtb_size;      // ~5005 (字节，实际 DTB 大小)
    uint64_t dtb_load_addr; // 0x84000000
    uint32_t fw_crc32;      // fw_payload.bin.v3patched 的 zlib CRC32
    uint32_t dtb_crc32;     // DTB 的 zlib CRC32
    uint8_t  reserved[436]; // 补齐到 512 字节
};
```

字节序：小端 (little-endian)，与 RISC-V 一致。  
生成工具：`scripts/gen_sd_manifest.py`

---

## 5. 关键地址常量

| 常量 | 值 | 说明 |
|------|-----|------|
| SDHCI_BASE | 0x60170000 | Rocket PA → PS SDIO1 |
| FW_LOAD_ADDR | 0x80000000 | fw_payload 加载目标 |
| DTB_LOAD_ADDR | 0x84000000 | DTB 加载目标 |
| FW_SIZE | 17,628,680 | fw_payload.bin.v3patched 字节数 |
| STAGE_MARK | 0x8F000000 | 调试 stage mark PA |
| P2_FW_OFFSET | 0x00100000 | fw 在 p2 内的字节偏移 |
| P2_DTB_OFFSET | 0x03000000 | DTB 在 p2 内的字节偏移 |

---

## 6. BOOT.BIN 构成 (p1)

```raw
BOOT.BIN
├── FSBL (First Stage Bootloader, ARM AArch64)
│   └── 执行 psu_init → 初始化 DDR/MIO/时钟 → 加载 bitstream
└── bitstream (.bit)
    └── PL fabric = Rocket SoC + BootROM ROM
                    BootROM 包含 sd_loader_v0 (编译后烧录进 BRAM)
```

> **sd_loader_v0 编进 BootROM / bitstream，不是 SD 卡上的文件。**  
> 每次修改 sd_loader_v0 需重新编译 BootROM 并用 `scripts/rebuild_bootrom.sh` 重建比特流。

---

## 7. 主机侧写入参考 (文档用途，不实际执行)

> ⚠️ 以下命令**仅供参考**，实际执行前请阅读 `docs/sd_card_partitioning_guide.md`。  
> 使用 `scripts/create_selfboot_sd_layout.sh --dry-run` 预览分区命令。  
> **绝对不要对生产 SD 卡直接执行 dd，除非已完整备份。**

```bash
# 假设 SD 卡在 /dev/sdX，p2 由 sgdisk 分配在 LBA=524288
P2_START=524288

# 生成 manifest
python3 scripts/gen_sd_manifest.py \
    --p2-start-lba ${P2_START} \
    --p2-sectors   524288 \
    --payload /path/to/fw_payload.bin.v3patched \
    --dtb     linux-bringup/dtb/chipyard-zcu104-linux-slip.dtb \
    --out     /tmp/manifest.bin

# 写入 manifest (p2 首扇区)
# sudo dd if=/tmp/manifest.bin of=/dev/sdX bs=512 seek=${P2_START} count=1 conv=notrunc

# 写入 fw_payload (p2 + 2048 扇区)
# sudo dd if=fw_payload.bin.v3patched of=/dev/sdX bs=512 seek=$((P2_START+2048)) conv=notrunc

# 写入 DTB (p2 + 98304 扇区)
# sudo dd if=zcu104.dtb of=/dev/sdX bs=512 seek=$((P2_START+98304)) conv=notrunc
```

---

## 8. 布局示意图

```raw
SD 卡 (≥ 32GB 推荐)
┌──────────────────────────────────────────────────────────┐
│ LBA 0    GPT Protective MBR                              │
│ LBA 1    GPT Primary Header                              │
│ LBA 2-33 GPT Partition Entries                           │
│ LBA 34+  [alignment gap]                                 │
├──────────────────────────────────────────────────────────┤
│ p1  FAT32  256MB  BOOT                                   │
│   └── BOOT.BIN (FSBL + bitstream with sd_loader_v0)     │
├──────────────────────────────────────────────────────────┤
│ p2  RAW    256MB  ROCKETBOOT                             │
│   ├── [+0x000000] manifest.bin         (512B, SDR0)      │
│   ├── [+0x100000] fw_payload.bin.v3    (16.82MB)         │
│   └── [+0x3000000] DTB                (~5KB)             │
├──────────────────────────────────────────────────────────┤
│ p3  BTRFS  rest   fedora                                 │
│   └── Fedora rootfs (subvol=root, mmcblk0p3)            │
└──────────────────────────────────────────────────────────┘
```

---

## 9. 不变约束

1. **sd_loader_v0 只用 PIO** — sdhci-caps-mask=0x10480000，禁止 DMA
2. **不解析任何文件系统** — p2 全程按扇区偏移读取
3. **p3 Fedora rootfs 不可修改** — `btrfs,subvol=root` 挂载参数保持不变
4. **p2 内偏移固定** — manifest@+0, fw@+0x100000, dtb@+0x3000000
5. **fw_payload.bin.v3patched SHA256 锁定** — `759db54b...`
6. **DTB 加载地址固定** — `0x84000000` (OpenSBI FW_PAYLOAD_FDT_ADDR 硬编码)

---

## 10. 下一步 (Phase C)

- 实现 `sd_loader_v0` C 代码 (sdhci.h/c, sdcard.c, crc32.c, sd_manifest.h, baremetal.c)
- 运行 `scripts/create_selfboot_sd_layout.sh --dry-run` 预览分区命令
- **人工执行** SD 卡分区和写入步骤（参见 `docs/sd_card_partitioning_guide.md`）
- 重建比特流 (`scripts/rebuild_bootrom.sh`)
