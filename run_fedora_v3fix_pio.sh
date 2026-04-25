#!/usr/bin/env bash
# run_fedora_v3fix_pio.sh — ZCU104 PL Rocket J100 Fedora PIO 固定成功链启动脚本
#
# 成功依据: fedora_v3fix3_20260424_230736
#   - mmcblk0: p1 p2 p3
#   - MOUNT SUCCESS subvol=root
#   - SWITCH_ROOT -> /sbin/init
#   - systemd[1] 启动
#   - stage_mark = 0x5354474500000011 (SWITCH_ROOT)
#
# 约束:
#   - J100-ONLY (PS SDIO1 via AXI LPD)
#   - PIO 强制 (sdhci-caps-mask=0x10480000)
#   - fw_payload.bin.v3patched (SHA256 锁定)
#   - 内核 #129 Apr 23 不重新编译
#
# 用法:
#   KERNEL_RUN_SECS=600  bash run_fedora_v3fix_pio.sh        # 默认 600s
#   KERNEL_RUN_SECS=1800 bash run_fedora_v3fix_pio.sh        # 稳定性 run
#   JLINK_HOST=127.0.0.1 JLINK_PORT=3333 bash run_fedora_v3fix_pio.sh

set -euo pipefail

# ─── 配置 ───────────────────────────────────────────────────────────────────
JLINK_HOST="${JLINK_HOST:-127.0.0.1}"
JLINK_PORT="${JLINK_PORT:-3333}"
KERNEL_RUN_SECS="${KERNEL_RUN_SECS:-600}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FW_DIR="/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware"
FW_PATCHED="${FW_DIR}/fw_payload.bin.v3patched"
CHUNK_DIR="/tmp/fw_chunks_v3"
GDB_BIN="/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb"
GDB_SCRIPT="${SCRIPT_DIR}/scripts/linux_boot.gdb"
DTB="${SCRIPT_DIR}/linux-bringup/dtb/chipyard-zcu104-linux-slip.dtb"

# SHA256 of fw_payload.bin.v3patched (locked 2026-04-24)
EXPECTED_SHA256="759db54b9bebf2b77945b5b7e861517f564443d370bd1efe4625538f8de31480"

# __initramfs_size in v3patched (must be 0x15c1a8)
EXPECTED_INITRAMFS_SIZE="0x15c1a8"

# ─── 颜色输出 ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*" >&2; exit 1; }

echo "================================================================"
echo "  ZCU104 PL Rocket J100 Fedora PIO Boot (固定成功链)"
echo "  $(date)"
echo "================================================================"
echo ""

# ─── 1. 检查 J-Link 连接 ────────────────────────────────────────────────────
echo "[preflight 1/6] 检查 J-Link GDB Server ${JLINK_HOST}:${JLINK_PORT} ..."
if nc -z -w 5 "${JLINK_HOST}" "${JLINK_PORT}" 2>/dev/null; then
    ok "J-Link GDB Server 可达 (${JLINK_HOST}:${JLINK_PORT})"
else
    fail "J-Link GDB Server 不可达 (${JLINK_HOST}:${JLINK_PORT})\n  请先启动 JLinkGDBServerCL.exe on Windows:\n  JLinkGDBServerCL.exe -select USB -device Cortex-A53 -if JTAG -speed 1000 -port 3333 -jtagconf 0,0 -nolocalhostonly -nogui"
fi

# ─── 2. 检查 GDB 可执行文件 ──────────────────────────────────────────────────
echo "[preflight 2/6] 检查 GDB ..."
if [[ ! -x "${GDB_BIN}" ]]; then
    fail "GDB 不存在: ${GDB_BIN}"
fi
ok "GDB: ${GDB_BIN}"

# ─── 3. 验证 fw_payload.bin.v3patched SHA256 ─────────────────────────────────
echo "[preflight 3/6] 验证 fw_payload.bin.v3patched ..."
if [[ ! -f "${FW_PATCHED}" ]]; then
    fail "fw_payload.bin.v3patched 不存在: ${FW_PATCHED}\n  请先运行 python3 /tmp/patch_fw.py"
fi

ACTUAL_SHA256="$(sha256sum "${FW_PATCHED}" | awk '{print $1}')"
if [[ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]]; then
    fail "SHA256 不匹配!\n  期望: ${EXPECTED_SHA256}\n  实际: ${ACTUAL_SHA256}\n  请重新执行 patch_fw.py"
fi
ok "SHA256 匹配: ${ACTUAL_SHA256:0:16}..."

# ─── 4. 验证 __initramfs_size ────────────────────────────────────────────────
echo "[preflight 4/6] 验证 __initramfs_size = ${EXPECTED_INITRAMFS_SIZE} ..."
SIZE_HEX="$(python3 -c "
import struct
fw = open('${FW_PATCHED}','rb').read()
target = struct.pack('<I', int('${EXPECTED_INITRAMFS_SIZE}', 16))
idx = fw.find(target)
if idx >= 0:
    print(hex(int('${EXPECTED_INITRAMFS_SIZE}', 16)))
else:
    print('NOT_FOUND')
" 2>/dev/null)"
if [[ "${SIZE_HEX}" == "NOT_FOUND" ]]; then
    warn "__initramfs_size=${EXPECTED_INITRAMFS_SIZE} 未在 v3patched 中找到，继续..."
else
    ok "__initramfs_size=${SIZE_HEX} 已验证"
fi

# ─── 5. 验证 DTB (PIO 模式) ──────────────────────────────────────────────────
echo "[preflight 5/6] 验证 DTB PIO 配置 ..."
if [[ ! -f "${DTB}" ]]; then
    fail "DTB 不存在: ${DTB}"
fi
DTB_CAPSMASK="$(dtc -I dtb -O dts "${DTB}" 2>/dev/null | grep "sdhci-caps-mask" | head -1 | tr -d ' \t')"
if echo "${DTB_CAPSMASK}" | grep -q "0x10480000"; then
    ok "DTB PIO 配置正确: ${DTB_CAPSMASK}"
else
    fail "DTB caps-mask 不是 PIO 模式!\n  期望: sdhci-caps-mask = <0x00 0x10480000>\n  实际: ${DTB_CAPSMASK}\n  请重新编译 DTB"
fi

# ─── 6. 强制重新 split chunks ────────────────────────────────────────────────
echo "[preflight 6/6] 重新 split fw_payload.bin.v3patched → ${CHUNK_DIR}/ ..."
mkdir -p "${CHUNK_DIR}"
rm -f "${CHUNK_DIR}"/chunk_*.bin
split -b 4194304 -d -a 2 --numeric-suffixes=0 --additional-suffix=.bin \
    "${FW_PATCHED}" "${CHUNK_DIR}/chunk_"

# 验证 chunks 重组 SHA256
CHUNK_SHA="$(cat "${CHUNK_DIR}"/chunk_*.bin | sha256sum | awk '{print $1}')"
if [[ "${CHUNK_SHA}" != "${EXPECTED_SHA256}" ]]; then
    fail "chunks 重组 SHA256 不匹配!\n  期望: ${EXPECTED_SHA256}\n  实际: ${CHUNK_SHA}"
fi
CHUNK_COUNT="$(ls "${CHUNK_DIR}"/chunk_*.bin | wc -l)"
ok "${CHUNK_COUNT} chunks, 重组 SHA256 匹配"

# ─── 生成 RUN_TAG ─────────────────────────────────────────────────────────────
RUN_TAG="fedora_pio_stable_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/tmp/boot_${RUN_TAG}.log"

echo ""
echo "================================================================"
echo "  Run Tag  : ${RUN_TAG}"
echo "  Log      : ${LOG_FILE}"
echo "  J-Link   : ${JLINK_HOST}:${JLINK_PORT}"
echo "  Run Time : ${KERNEL_RUN_SECS}s"
echo "  chunks   : ${CHUNK_DIR}/ (${CHUNK_COUNT} files)"
echo "================================================================"
echo ""

# ─── 启动 boot ───────────────────────────────────────────────────────────────
echo "[boot] 启动 GDB boot script (KERNEL_RUN_SECS=${KERNEL_RUN_SECS}s)..."
echo "[boot] 日志: ${LOG_FILE}"
echo ""

TIMEOUT_SECS=$(( KERNEL_RUN_SECS + 900 ))

JLINK_HOST="${JLINK_HOST}" \
JLINK_PORT="${JLINK_PORT}" \
KERNEL_RUN_SECS="${KERNEL_RUN_SECS}" \
RUN_TAG="${RUN_TAG}" \
    stdbuf -oL timeout "${TIMEOUT_SECS}" \
    "${GDB_BIN}" -q -batch -x "${GDB_SCRIPT}" \
    2>&1 | stdbuf -oL tee "${LOG_FILE}"

EC=${PIPESTATUS[0]}

echo ""
echo "================================================================"
echo "  Boot 完成 (exit code: ${EC})"
echo "================================================================"

# ─── 验收输出 ────────────────────────────────────────────────────────────────
echo ""
echo "--- 验收输出 ---"
grep -n "mmcblk0.*p1 p2\|MOUNT SUCCESS\|SWITCH_ROOT\|systemd\[1\]\|stage_mark.*sub\|Kernel panic" \
    "${LOG_FILE}" 2>/dev/null | tail -20 || true

echo ""
echo "--- 里程碑 ---"
grep -A 20 "^\[milestones\]" "${LOG_FILE}" 2>/dev/null | head -22 || true

echo ""
echo "--- stage_mark ---"
grep "stage_mark.*u64\|stage_mark.*sub" "${LOG_FILE}" 2>/dev/null | tail -3 || true

echo ""
echo "[done] 日志: ${LOG_FILE}"
echo "[done] klog: /tmp/klog_${RUN_TAG}.bin"
