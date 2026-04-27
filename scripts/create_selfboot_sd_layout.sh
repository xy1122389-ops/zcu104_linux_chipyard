#!/usr/bin/env bash
# create_selfboot_sd_layout.sh — ZCU104 自引导 SD 卡分区布局工具
#
# 三分区方案:
#   p1: FAT32   256MB  label=BOOT         — BOOT.BIN (FSBL + bitstream)
#   p2: RAW     256MB  label=ROCKETBOOT   — manifest + fw_payload + DTB
#   p3: BTRFS   rest   label=fedora       — Fedora rootfs
#
# 默认: DRY-RUN (只打印命令，不执行)
# 执行需要: --execute，并输入 YES_DESTROY_SD_CARD 确认
#
# 用法:
#   ./create_selfboot_sd_layout.sh --disk /dev/sdX [--p1-size 256M] [--p2-size 256M]
#   ./create_selfboot_sd_layout.sh --disk /dev/sdX --execute
#
# 警告: --execute 会完全清除目标磁盘！

set -euo pipefail

# ── 默认参数 ────────────────────────────────────────────────────────────────
DISK=""
P1_SIZE="256M"
P2_SIZE="256M"
EXECUTE=0

usage() {
    echo "用法: $0 --disk /dev/sdX [--p1-size 256M] [--p2-size 256M] [--execute]"
    echo ""
    echo "  --disk      目标 SD 卡设备 (必须，例如 /dev/sdb)"
    echo "  --p1-size   p1 FAT32 大小 (默认: 256M)"
    echo "  --p2-size   p2 RAW 大小   (默认: 256M)"
    echo "  --execute   实际执行 (默认 dry-run，执行时需二次确认)"
    echo ""
    echo "三分区布局:"
    echo "  p1: FAT32  \${P1_SIZE}  BOOT       — BOOT.BIN"
    echo "  p2: RAW    \${P2_SIZE}  ROCKETBOOT — manifest+fw+dtb"
    echo "  p3: BTRFS  rest        fedora     — Fedora rootfs"
    exit 1
}

# ── 参数解析 ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk)    DISK="$2"; shift 2 ;;
        --p1-size) P1_SIZE="$2"; shift 2 ;;
        --p2-size) P2_SIZE="$2"; shift 2 ;;
        --execute) EXECUTE=1; shift ;;
        --help|-h) usage ;;
        *) echo "未知参数: $1"; usage ;;
    esac
done

[[ -z "$DISK" ]] && { echo "ERROR: --disk 必须指定"; usage; }

# ── 警告横幅 ────────────────────────────────────────────────────────────────
cat << 'WARN'

╔══════════════════════════════════════════════════════════════════════╗
║  WARNING: THIS SCRIPT WILL DESTROY THE TARGET DISK IF RUN WITH     ║
║  --execute                                                           ║
║                                                                      ║
║  ZCU104 三分区方案:                                                  ║
║    p1: FAT32   256MB  BOOT       — BOOT.BIN                          ║
║    p2: RAW     256MB  ROCKETBOOT — manifest + fw_payload + DTB       ║
║    p3: BTRFS   rest   fedora     — Fedora rootfs                     ║
║                                                                      ║
║  p2 不格式化，sd_loader_v0 直接按扇区偏移读取。                     ║
║  现有 SD 卡数据将全部丢失。备份后再继续。                           ║
╚══════════════════════════════════════════════════════════════════════╝

WARN

echo "目标磁盘: ${DISK}"
echo "p1 大小:  ${P1_SIZE} (FAT32)"
echo "p2 大小:  ${P2_SIZE} (RAW, 无文件系统)"
echo "p3 大小:  剩余全部 (BTRFS)"
echo ""

# ── 检查磁盘是否存在（仅 dry-run 时也检查格式，不要求真实设备） ──────────
if [[ $EXECUTE -eq 1 ]]; then
    if [[ ! -b "$DISK" ]]; then
        echo "ERROR: ${DISK} 不是块设备"
        exit 1
    fi
    # 检查依赖工具
    for cmd in sgdisk mkfs.fat; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "ERROR: 缺少工具: $cmd  (apt install gdisk dosfstools)"
            exit 1
        fi
    done
fi

# ── 生成命令列表 ─────────────────────────────────────────────────────────────
CMDS=()

# 1. 清除并创建新 GPT
CMDS+=("sgdisk --zap-all ${DISK}")
CMDS+=("sgdisk --clear ${DISK}")

# 2. 创建三个分区
CMDS+=("sgdisk -n 1:0:+${P1_SIZE}  -t 1:0700 -c 1:BOOT       ${DISK}")
CMDS+=("sgdisk -n 2:0:+${P2_SIZE}  -t 2:8300 -c 2:ROCKETBOOT ${DISK}")
CMDS+=("sgdisk -n 3:0:0            -t 3:8300 -c 3:fedora      ${DISK}")

# 3. 刷新分区表
CMDS+=("partprobe ${DISK} || blockdev --rereadpt ${DISK}")
CMDS+=("sleep 2")

# 4. 格式化 p1 (FAT32)
CMDS+=("mkfs.fat -F 32 -n BOOT ${DISK}p1")

# 5. p2 不格式化 (RAW for sd_loader_v0)
CMDS+=("echo '[p2 RAW: 跳过格式化 — sd_loader_v0 直接按扇区读取]'")

# 6. 格式化 p3 (BTRFS) — 由 Fedora 安装提供，这里仅作占位
CMDS+=("# mkfs.btrfs -L fedora ${DISK}p3  # 由 Fedora rootfs 恢复步骤处理")

# 7. 打印 p2 起始 LBA (供 gen_sd_manifest.py 使用)
CMDS+=("echo '=== p2 (ROCKETBOOT) 分区信息 ==='" )
CMDS+=("sgdisk -p ${DISK} | grep ROCKETBOOT")
CMDS+=("P2_START=\$(sgdisk -p ${DISK} | awk '/ROCKETBOOT/{print \$2}')")
CMDS+=("echo \"p2_start_lba=\${P2_START}\"")
CMDS+=("echo \"下一步: python3 scripts/gen_sd_manifest.py --p2-start-lba \${P2_START} --p2-sectors 524288 ...\"")

# ── 打印命令 ────────────────────────────────────────────────────────────────
if [[ $EXECUTE -eq 0 ]]; then
    echo "══════════════ DRY-RUN 模式 (不执行任何操作) ══════════════"
    echo ""
    echo "将要执行的命令:"
    echo ""
    for i in "${!CMDS[@]}"; do
        printf "  [%02d] %s\n" "$((i+1))" "${CMDS[$i]}"
    done
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "要实际执行，请运行:"
    echo "  $0 --disk ${DISK} --execute"
    echo ""
    echo "注意: 执行后需要人工写入内容:"
    echo "  1. 将 BOOT.BIN 复制到 p1 (FAT32)"
    echo "  2. 运行 gen_sd_manifest.py 生成 manifest.bin"
    echo "  3. 写入 manifest / fw_payload / DTB 到 p2"
    echo "  4. 恢复 Fedora rootfs 到 p3"
    exit 0
fi

# ── 执行模式：二次确认 ───────────────────────────────────────────────────────
echo ""
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "!! EXECUTE 模式已激活                                        !!"
echo "!! 磁盘 ${DISK} 上的所有数据将被永久删除！                   !!"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo ""
echo -n "输入 YES_DESTROY_SD_CARD 继续（其他任何输入取消）: "
read -r CONFIRM

if [[ "$CONFIRM" != "YES_DESTROY_SD_CARD" ]]; then
    echo "取消操作。"
    exit 0
fi

echo ""
echo "开始执行..."
for cmd in "${CMDS[@]}"; do
    # 跳过注释行
    [[ "$cmd" == \#* ]] && { echo "[SKIP] $cmd"; continue; }
    echo "[EXEC] $cmd"
    eval "$cmd"
done

echo ""
echo "=== 分区创建完成 ==="
echo ""
echo "下一步 (人工操作):"
echo "  1. 获取 p2 起始 LBA:"
echo "     sgdisk -p ${DISK} | grep ROCKETBOOT"
echo "  2. 生成并写入 manifest:"
echo "     python3 scripts/gen_sd_manifest.py --p2-start-lba <LBA> --p2-sectors 524288 \\"
echo "         --payload fw_payload.bin.v3patched --dtb zcu104.dtb --out /tmp/manifest.bin"
echo "  3. 写入 manifest/fw/dtb 到 p2 (参见 docs/sd_card_partitioning_guide.md)"
echo "  4. 复制 BOOT.BIN 到 p1"
echo "  5. 恢复 Fedora rootfs 到 p3"
