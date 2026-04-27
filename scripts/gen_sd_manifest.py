#!/usr/bin/env python3
"""
gen_sd_manifest.py — 生成 sd_loader_v0 所需的 512 字节 Manifest

SD 卡三分区方案 (ZCU104 自定义稳定方案):
  p1: FAT32  256MB  BOOT       — BOOT.BIN (FSBL + bitstream)
  p2: RAW    256MB  ROCKETBOOT — manifest + fw_payload + DTB
  p3: BTRFS  rest   fedora     — Fedora rootfs

p2 内部固定扇区偏移:
  manifest : +0        (+0x00000000)
  fw       : +2048     (+0x00100000)  [0x100000/512]
  dtb      : +98304    (+0x03000000)  [0x3000000/512]

用法:
  python3 gen_sd_manifest.py \
      --p2-start-lba 524288 \
      --p2-sectors   524288 \
      --payload fw_payload.bin.v3patched \
      --dtb     chipyard-zcu104-linux-slip.dtb \
      --out     /tmp/manifest.bin
"""

import argparse, struct, zlib, sys, os, json

MANIFEST_MAGIC        = 0x53445230
MANIFEST_VERSION      = 0x00000001
MANIFEST_SIZE         = 512
MANIFEST_STRUCT       = "<IIQQQQQQII"
MANIFEST_HEADER_BYTES = struct.calcsize(MANIFEST_STRUCT)  # 72 bytes

P2_MANIFEST_SECTOR_OFFSET = 0
P2_FW_SECTOR_OFFSET       = 2048     # 0x00100000 / 512
P2_DTB_SECTOR_OFFSET      = 98304    # 0x03000000 / 512

FW_LOAD_ADDR  = 0x80000000
DTB_LOAD_ADDR = 0x84000000


def crc32_file(path):
    crc = 0
    with open(path, "rb") as f:
        while True:
            chunk = f.read(1 << 20)
            if not chunk:
                break
            crc = zlib.crc32(chunk, crc)
    return crc & 0xFFFFFFFF


def sectors(n):
    return (n + 511) // 512


def main():
    parser = argparse.ArgumentParser(description="生成 sd_loader_v0 Manifest (三分区方案)")
    parser.add_argument("--p2-start-lba", type=int, required=True,
                        help="p2 (ROCKETBOOT) 分区起始 LBA")
    parser.add_argument("--p2-sectors",   type=int, required=True,
                        help="p2 分区总扇区数")
    parser.add_argument("--payload",      required=True,
                        help="fw_payload.bin.v3patched 路径")
    parser.add_argument("--dtb",          required=True,
                        help="DTB 文件路径")
    parser.add_argument("--out",          required=True,
                        help="输出 manifest.bin 路径")
    parser.add_argument("--disk-info-json",
                        help="[高级] 包含 p2 分区信息的 JSON 文件")
    args = parser.parse_args()

    if args.disk_info_json:
        with open(args.disk_info_json) as f:
            info = json.load(f)
        p2 = info.get("partitions", {}).get("2", {})
        if p2:
            args.p2_start_lba = int(p2["start"])
            args.p2_sectors   = int(p2["size"])
            print(f"[disk-info-json] p2_start_lba={args.p2_start_lba}  p2_sectors={args.p2_sectors}")

    p2_start = args.p2_start_lba
    p2_secs  = args.p2_sectors
    p2_end   = p2_start + p2_secs - 1

    # 文件检查
    ok = True
    for path, name in [(args.payload, "--payload"), (args.dtb, "--dtb")]:
        if not os.path.isfile(path):
            print(f"ERROR: {name} not found: {path}", file=sys.stderr)
            ok = False
    if not ok:
        sys.exit(1)

    fw_size  = os.path.getsize(args.payload)
    dtb_size = os.path.getsize(args.dtb)

    manifest_lba = p2_start + P2_MANIFEST_SECTOR_OFFSET
    fw_lba       = p2_start + P2_FW_SECTOR_OFFSET
    dtb_lba      = p2_start + P2_DTB_SECTOR_OFFSET
    fw_end_lba   = fw_lba  + sectors(fw_size)  - 1
    dtb_end_lba  = dtb_lba + sectors(dtb_size) - 1

    # 安全检查
    errors = []
    if p2_start < 2048:
        errors.append(f"p2_start_lba={p2_start} < 2048 — 会覆盖 GPT 元数据！")
    if fw_end_lba > p2_end:
        errors.append(f"fw_payload 末 LBA {fw_end_lba} 超出 p2 末 LBA {p2_end}")
    if dtb_end_lba > p2_end:
        errors.append(f"DTB 末 LBA {dtb_end_lba} 超出 p2 末 LBA {p2_end}")
    if dtb_lba < fw_end_lba:
        errors.append(f"dtb_lba {dtb_lba} 与 fw_payload 末 {fw_end_lba} 重叠")
    min_required = P2_DTB_SECTOR_OFFSET + sectors(dtb_size)
    if p2_secs < min_required:
        errors.append(f"p2 仅 {p2_secs} 扇区，需至少 {min_required} 扇区")
    if errors:
        print("ERROR: 安全检查失败：", file=sys.stderr)
        for e in errors:
            print(f"  • {e}", file=sys.stderr)
        sys.exit(1)

    print(f"[gen_sd_manifest] 计算 CRC32（fw 约 16MB，可能需要几秒）...")
    fw_crc32  = crc32_file(args.payload)
    dtb_crc32 = crc32_file(args.dtb)

    print()
    print("══════════════════ DRY-RUN 报告 ══════════════════")
    print(f"  p2_start_lba   = {p2_start}")
    print(f"  p2_end_lba     = {p2_end}  (total {p2_secs} sectors, {p2_secs*512//1024//1024} MB)")
    print()
    print(f"  manifest_lba   = {manifest_lba}  (+0  from p2 start)")
    print(f"  fw_lba         = {fw_lba}  (+{P2_FW_SECTOR_OFFSET} from p2 start, +0x100000)")
    print(f"  fw_end_lba     = {fw_end_lba}")
    print(f"  fw_size        = {fw_size} bytes ({sectors(fw_size)} sectors)")
    print(f"  fw_crc32       = 0x{fw_crc32:08x}")
    print(f"  fw_load_addr   = 0x{FW_LOAD_ADDR:08x}")
    print()
    print(f"  dtb_lba        = {dtb_lba}  (+{P2_DTB_SECTOR_OFFSET} from p2 start, +0x3000000)")
    print(f"  dtb_end_lba    = {dtb_end_lba}")
    print(f"  dtb_size       = {dtb_size} bytes ({sectors(dtb_size)} sectors)")
    print(f"  dtb_crc32      = 0x{dtb_crc32:08x}")
    print(f"  dtb_load_addr  = 0x{DTB_LOAD_ADDR:08x}")
    print()
    gap = dtb_lba - fw_end_lba - 1
    free = p2_secs - (dtb_end_lba - p2_start + 1)
    print(f"  gap fw→dtb     = {gap} sectors ({gap*512//1024} KB)")
    print(f"  p2 free after  = {free} sectors ({free*512//1024//1024} MB)")
    print("═══════════════════════════════════════════════════")
    print()
    print("建议写入命令 (不执行，仅供参考，SD_DEV 替换为实际设备):")
    print(f"  # 写 manifest (p2 首扇区):")
    print(f"  sudo dd if={args.out} of=/dev/SD_DEV bs=512 seek={manifest_lba} count=1 conv=notrunc")
    print(f"  # 写 fw_payload (+0x100000):")
    print(f"  sudo dd if={args.payload} of=/dev/SD_DEV bs=512 seek={fw_lba} conv=notrunc status=progress")
    print(f"  # 写 DTB (+0x3000000):")
    print(f"  sudo dd if={args.dtb} of=/dev/SD_DEV bs=512 seek={dtb_lba} conv=notrunc")
    print()

    # 打包 Manifest
    header = struct.pack(
        MANIFEST_STRUCT,
        MANIFEST_MAGIC, MANIFEST_VERSION,
        fw_lba, fw_size, FW_LOAD_ADDR,
        dtb_lba, dtb_size, DTB_LOAD_ADDR,
        fw_crc32, dtb_crc32,
    )
    assert len(header) == MANIFEST_HEADER_BYTES
    manifest = header + b'\x00' * (MANIFEST_SIZE - MANIFEST_HEADER_BYTES)
    assert len(manifest) == MANIFEST_SIZE

    with open(args.out, "wb") as f:
        f.write(manifest)

    print(f"[OK] {args.out} written ({MANIFEST_SIZE} bytes)")
    print(f"     magic=SDR0  fw_crc32=0x{fw_crc32:08x}  dtb_crc32=0x{dtb_crc32:08x}")


if __name__ == "__main__":
    main()
