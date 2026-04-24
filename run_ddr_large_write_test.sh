#!/usr/bin/env bash
# run_ddr_large_write_test.sh — DDR 大数据写入完整性实验运行脚本
#
# 使用方法:
#   bash run_ddr_large_write_test.sh [--skip-init]
#
# 选项:
#   --skip-init  跳过 stable_init.sh (板卡已初始化时使用)
#
# 环境变量:
#   JLINK_HOST  J-Link GDB Server IP (默认 127.0.0.1)
#   JLINK_PORT  J-Link GDB Server port (默认 3333)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JLINK_HOST="${JLINK_HOST:-127.0.0.1}"
JLINK_PORT="${JLINK_PORT:-3333}"
SKIP_INIT=0

for arg in "$@"; do
    case "$arg" in
        --skip-init) SKIP_INIT=1 ;;
        *) echo "未知参数: $arg" && exit 1 ;;
    esac
done

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/tmp/ddr_large_write_test_${TIMESTAMP}.log"

echo "========================================"
echo "DDR 大数据写入完整性实验"
echo "时间: $(date)"
echo "J-Link: ${JLINK_HOST}:${JLINK_PORT}"
echo "日志: ${LOG_FILE}"
echo "========================================"

# ---- Step 1: 板卡初始化 (可选) ----
if [[ $SKIP_INIT -eq 0 ]]; then
    echo ""
    echo "=== Step 1: 运行 stable_init.sh ==="
    if [[ -f scripts/stable_init.sh ]]; then
        bash scripts/stable_init.sh 2>&1 | tee -a "$LOG_FILE"
        echo "=== stable_init 完成 ==="
    else
        echo "[ERROR] 未找到 scripts/stable_init.sh"
        exit 1
    fi
    # 等待板卡稳定
    echo "等待 3 秒让板卡稳定..."
    sleep 3
else
    echo "=== Step 1: 跳过 stable_init (--skip-init) ==="
fi

# ---- Step 2: 验证 J-Link 可达 ----
echo ""
echo "=== Step 2: 验证 J-Link GDB Server ==="
if ! nc -z -w 3 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
    echo "[ERROR] J-Link GDB Server 不可达: ${JLINK_HOST}:${JLINK_PORT}"
    echo "  请确保 Windows 侧 J-Link GDB Server 已启动"
    echo "  启动命令示例 (在 WSL): powershell.exe -Command 'Start-Process ...'"
    exit 1
fi
echo "[ok] J-Link GDB Server 可达: ${JLINK_HOST}:${JLINK_PORT}"

# ---- Step 3: 确认 GDB 可用 ----
GDB_BIN=""
for gdb_candidate in \
    riscv64-unknown-elf-gdb \
    /root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb \
    riscv64-linux-gnu-gdb \
    /opt/riscv/bin/riscv64-unknown-elf-gdb; do
    if command -v "$gdb_candidate" &>/dev/null || [[ -x "$gdb_candidate" ]]; then
        GDB_BIN="$gdb_candidate"
        break
    fi
done

if [[ -z "$GDB_BIN" ]]; then
    echo "[ERROR] 未找到 RISC-V GDB, 请确保工具链已安装"
    exit 1
fi
echo "[ok] 使用 GDB: $GDB_BIN"

# ---- Step 4: 运行 DDR 大数据写入测试 ----
echo ""
echo "=== Step 3: 运行 DDR 大数据写入完整性测试 ==="
echo "  预计耗时: ~5-8 分钟 (含两次 SBA 写 + CPU 循环)"
echo ""

CHIPYARD_ZCU104_CFG="RocketZCU104LinuxBringupConfig" \
JLINK_HOST="$JLINK_HOST" \
JLINK_PORT="$JLINK_PORT" \
    "$GDB_BIN" \
    --batch \
    -x scripts/ddr_large_write_test.gdb \
    2>&1 | tee "$LOG_FILE"

EXIT_CODE=${PIPESTATUS[0]}

echo ""
echo "========================================"
echo "实验完成. 退出码: $EXIT_CODE"
echo "日志保存在: $LOG_FILE"
echo "========================================"

# 提取最终报告
echo ""
echo "=== 最终报告摘要 ==="
grep -E "Phase [ABC]|结论:|PASS|FAIL|SBA 写入" "$LOG_FILE" | tail -20 || true

exit $EXIT_CODE
