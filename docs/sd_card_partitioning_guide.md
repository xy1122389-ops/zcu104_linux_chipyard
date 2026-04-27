# SD 卡分区操作指南 — ZCU104 自引导三分区方案

**版本**: v1  
**日期**: 2026-04-25  
**状态**: 参考文档，所有命令仅供阅读，不实际执行

---

> ⚠️ **重要提醒**  
> 本文档中的所有 `sgdisk`、`dd`、`mkfs` 命令**仅作文档记录**。  
> 在真实执行前，必须：  
> 1. 确认目标设备是正确的 SD 卡（不是系统盘）  
> 2. 完整备份 SD 卡上的所有数据  
> 3. 使用 `create_selfboot_sd_layout.sh --dry-run` 预览命令  
> 4. 明确理解每个步骤的影响后再执行

---

## 1. 识别 SD 卡设备

将 SD 卡插入读卡器后，在 Linux 主机上识别设备：

```bash
# 查看最近插入的块设备
lsblk -d -o NAME,SIZE,MODEL,TRAN | grep -E "sd|mmc"

# 或查看内核日志
dmesg | tail -20 | grep -E "sd[a-z]|mmc"

# 确认设备大小
sudo fdisk -l /dev/sdX | head -5
# 输出示例: Disk /dev/sdb: 59.49 GiB, 63864569856 bytes, 124735488 sectors
```

> **安全规则**：永远不要对 `/dev/sda` 或者大于 200GB 的设备执行操作。  
> SD 卡通常在 `/dev/sdb`、`/dev/sdc` 或 `/dev/mmcblk0`。

---

## 2. 备份现有 SD 卡

在任何分区操作前，先做完整备份：

```bash
SD_DEV=/dev/sdX        # 替换为实际设备
BACKUP=/path/to/backup/sd_backup_$(date +%Y%m%d).img.gz

# 完整备份 (压缩)
sudo dd if=${SD_DEV} bs=4M status=progress | gzip > ${BACKUP}
echo "备份大小: $(du -h ${BACKUP})"

# 验证备份完整性
gzip -t ${BACKUP} && echo "备份文件完整"
```

恢复备份：

```bash
# 从备份恢复 (会覆盖整个 SD 卡！)
# gzip -dc ${BACKUP} | sudo dd of=${SD_DEV} bs=4M status=progress
```

---

## 3. 三分区方案说明

| 分区 | 类型   | 大小  | Label      | 用途 |
|------|--------|-------|------------|------|
| p1   | FAT32  | 256MB | BOOT       | PS ARM 启动：BOOT.BIN (FSBL + bitstream) |
| p2   | RAW    | 256MB | ROCKETBOOT | Rocket sd_loader_v0 读取：manifest + fw_payload + DTB |
| p3   | BTRFS  | 剩余  | fedora     | Fedora rootfs (subvol=root，Linux 挂载 /dev/mmcblk0p3) |

### 为什么 p2 不格式化？

`sd_loader_v0` 运行在 Rocket BootROM 内（PA 0x10000），此时 Linux 尚未启动，  
无任何文件系统驱动。它直接通过 SDHCI PIO 按固定扇区偏移读取数据：

```
p2 内固定偏移:
  +0x00000000 (LBA p2_start +    0) → manifest.bin   (512 字节)
  +0x00100000 (LBA p2_start + 2048) → fw_payload     (16.82 MB)
  +0x03000000 (LBA p2_start +98304) → DTB            (~5 KB)
```

---

## 4. 创建分区 (预览命令)

使用 `scripts/create_selfboot_sd_layout.sh` 工具：

```bash
# 先 dry-run 查看将要执行的命令
./scripts/create_selfboot_sd_layout.sh --disk /dev/sdX

# 实际执行 (需要二次确认 YES_DESTROY_SD_CARD)
# ./scripts/create_selfboot_sd_layout.sh --disk /dev/sdX --execute
```

等效的手工 sgdisk 命令 (参考):

```bash
SD_DEV=/dev/sdX

# 清除并重建 GPT
# sudo sgdisk --zap-all ${SD_DEV}
# sudo sgdisk --clear   ${SD_DEV}

# 创建三个分区
# sudo sgdisk -n 1:0:+256M  -t 1:0700 -c 1:BOOT       ${SD_DEV}   # p1 FAT32
# sudo sgdisk -n 2:0:+256M  -t 2:8300 -c 2:ROCKETBOOT ${SD_DEV}   # p2 RAW
# sudo sgdisk -n 3:0:0      -t 3:8300 -c 3:fedora      ${SD_DEV}   # p3 BTRFS rest

# 刷新分区表
# sudo partprobe ${SD_DEV}
```

---

## 5. 格式化 p1 (FAT32)

```bash
SD_DEV=/dev/sdX

# 格式化 p1 为 FAT32
# sudo mkfs.fat -F 32 -n BOOT ${SD_DEV}p1

# 验证
# sudo blkid ${SD_DEV}p1
# 期望: TYPE="vfat"  LABEL="BOOT"
```

---

## 6. p2 为什么不格式化

p2 (`ROCKETBOOT`) 是 RAW 分区，不创建任何文件系统。  
内容通过 `dd` 直接写入扇区：

- `sd_loader_v0` 通过扫描 GPT 找到 `ROCKETBOOT` 分区的起始 LBA
- 然后按固定偏移读取 manifest、fw_payload、DTB
- 无需文件系统，简化代码，减少 BootROM 大小

---

## 7. 计算 p2_start_lba

分区创建后，获取 p2 起始 LBA：

```bash
SD_DEV=/dev/sdX

# 方法 1: sgdisk
sudo sgdisk -p ${SD_DEV} | grep ROCKETBOOT
# 示例输出:   2  524288  1048575   256.0 MiB  8300  ROCKETBOOT
# p2_start_lba = 524288

# 方法 2: fdisk
sudo fdisk -l ${SD_DEV} | grep "${SD_DEV}p2"
# 示例输出: /dev/sdbp2  524288  1048575  524288  256M  Linux filesystem
# Start = 524288

# 方法 3: sfdisk
sudo sfdisk -d ${SD_DEV} | grep "${SD_DEV}p2"
# 示例输出: /dev/sdbp2 : start=      524288, ...
```

---

## 8. 生成并写入 manifest

获取 p2_start_lba 后，生成 manifest.bin：

```bash
P2_START=524288   # 替换为实际值
SD_DEV=/dev/sdX
FW=/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin.v3patched
DTB=/root/chipyard/fpga/linux-bringup/dtb/chipyard-zcu104-linux-slip.dtb

# 生成 manifest (会打印 dry-run 报告和建议 dd 命令)
python3 scripts/gen_sd_manifest.py \
    --p2-start-lba ${P2_START} \
    --p2-sectors   524288 \
    --payload      ${FW} \
    --dtb          ${DTB} \
    --out          /tmp/manifest.bin

# 写入 manifest 到 p2 首扇区
# sudo dd if=/tmp/manifest.bin of=${SD_DEV} bs=512 seek=${P2_START} count=1 conv=notrunc

# 写入 fw_payload 到 p2 + 2048 扇区 (+0x100000)
# sudo dd if=${FW} of=${SD_DEV} bs=512 seek=$((P2_START+2048)) conv=notrunc status=progress

# 写入 DTB 到 p2 + 98304 扇区 (+0x3000000)
# sudo dd if=${DTB} of=${SD_DEV} bs=512 seek=$((P2_START+98304)) conv=notrunc

# 同步
# sync
```

---

## 9. 验证写入

```bash
P2_START=524288
SD_DEV=/dev/sdX

# 验证 manifest magic (SDR0 = 53 44 52 30 小端 = 30 52 44 53)
sudo dd if=${SD_DEV} bs=512 skip=${P2_START} count=1 2>/dev/null | xxd | head -3
# 期望第一行: 00000000: 3052 4453 0100 0000 ...

# 验证 fw_payload SHA256
sudo dd if=${SD_DEV} bs=512 skip=$((P2_START+2048)) count=34432 2>/dev/null | \
    dd bs=1 count=17628680 2>/dev/null | sha256sum
# 期望: 759db54b9bebf2b77945b5b7e861517f564443d370bd1efe4625538f8de31480

# 验证 DTB magic (D0 0D FE ED)
sudo dd if=${SD_DEV} bs=512 skip=$((P2_START+98304)) count=1 2>/dev/null | xxd | head -2
# 期望: 00000000: d00d feed ...
```

---

## 10. 写入 BOOT.BIN 到 p1

```bash
SD_DEV=/dev/sdX
BOOT_BIN=/path/to/BOOT.BIN   # 包含 FSBL + bitstream (sd_loader_v0 编入 bitstream)

# 挂载 p1
# sudo mkdir -p /mnt/sdboot
# sudo mount ${SD_DEV}p1 /mnt/sdboot

# 复制 BOOT.BIN
# sudo cp ${BOOT_BIN} /mnt/sdboot/BOOT.BIN

# 卸载
# sudo umount /mnt/sdboot
```

> **注意**: BOOT.BIN 中的 bitstream 包含 Rocket BootROM，  
> BootROM 内嵌了 sd_loader_v0 代码。  
> 修改 sd_loader_v0 → 重新编译 BootROM → 重建 bitstream → 更新 BOOT.BIN。

---

## 11. 恢复 Fedora rootfs 到 p3

p3 (BTRFS, label=fedora) 需要从备份恢复 Fedora rootfs：

```bash
SD_DEV=/dev/sdX
FEDORA_BACKUP=/path/to/fedora_rootfs.tar.zst   # 或 btrfs send/receive 备份

# 方案 A: btrfs send/receive
# sudo mkfs.btrfs -L fedora ${SD_DEV}p3
# sudo mkdir -p /mnt/sdp3
# sudo mount ${SD_DEV}p3 /mnt/sdp3
# sudo btrfs receive /mnt/sdp3 < fedora_rootfs.btrfs
# sudo umount /mnt/sdp3

# 方案 B: tar 恢复 (需要与原 btrfs subvolume 结构一致)
# sudo mkfs.btrfs -L fedora ${SD_DEV}p3
# sudo mount -o subvol=/ ${SD_DEV}p3 /mnt/sdp3
# sudo tar -xzf ${FEDORA_BACKUP} -C /mnt/sdp3
# sudo umount /mnt/sdp3
```

---

## 12. 验收：上电自引导流程

完成所有步骤后，将 SD 卡插入 ZCU104，通过 UART 观察启动日志：

```
期望看到:
[sdboot] sd_loader_v0 start
[sdboot] sdhci reset ok
[sdboot] card init ok
[sdboot] p2 found
[sdboot] manifest ok
[sdboot] loading fw_payload...
[sdboot] fw ok
[sdboot] fw crc32 ok
[sdboot] dtb ok
(OpenSBI 启动信息)
Linux version 6.6.0 ...
(Fedora 启动信息)
systemd[1]: ...
```

如果看到 `FATAL:` 消息，参考 `docs/sd_selfboot_acceptance_criteria.md` 排查。

---

## 附录: 快速参考

| 步骤 | 工具 | 命令 |
|------|------|------|
| 预览分区命令 | create_selfboot_sd_layout.sh | `--dry-run` |
| 创建分区 | create_selfboot_sd_layout.sh | `--execute` + `YES_DESTROY_SD_CARD` |
| 获取 p2_start_lba | sgdisk | `sgdisk -p /dev/sdX \| grep ROCKETBOOT` |
| 生成 manifest | gen_sd_manifest.py | `--p2-start-lba ... --p2-sectors ...` |
| 写 manifest | dd | `seek=${P2_START}` |
| 写 fw_payload | dd | `seek=$((P2_START+2048))` |
| 写 DTB | dd | `seek=$((P2_START+98304))` |
| 验证 manifest | dd + xxd | magic = `3052 4453` |
| 验证 fw SHA256 | dd + sha256sum | `759db54b...` |
