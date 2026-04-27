# phase2_check_rocket_pc.gdb
#
# Phase 2: 用 J-Link 只读检查 Rocket PC
#
# 目标: 确认 Rocket CPU 是否进入 sd_loader_v0 BootROM
#       不加载任何 payload，不修改任何内存
#
# 前提:
#   1. Phase 1 已通过 (bitstream 已加载，PS-PL 隔离已移除)
#   2. J-Link GDB Server 已启动 (port 3333)
#
# 运行方式:
#   bash scripts/phase2_check_rocket_pc.sh
#   或者:
#   JLINK_HOST=127.0.0.1 JLINK_PORT=3333 \
#     riscv64-unknown-elf-gdb -batch -x scripts/phase2_check_rocket_pc.gdb
#
# 成功标准:
#   PC 落在 BootROM 范围 (0x00001000~0x00001FFF 或 TLROM 地址)
#   或者进入 sd_loader 地址 (0x10000~0x20000 或类似)
#   或者 PC = 0x80000000 (如果 payload 已在 DDR，跳转了)

set pagination off
set confirm off
set remotetimeout 20

# 连接 J-Link GDB Server (127.0.0.1:3333 via WSL2 mirrored networking)
python
import os
host = os.environ.get("JLINK_HOST", "127.0.0.1")
port = os.environ.get("JLINK_PORT", "3333")
gdb.execute(f"target remote {host}:{port}")
end

echo [Phase 2] Connected to J-Link GDB Server\n

# 不 halt (如果 Rocket 正在运行)
# 先检查是否已经停止
python
try:
    pc = gdb.parse_and_eval("$pc")
    print(f"[Phase 2] Current PC = {hex(int(pc))}")
except Exception as e:
    print(f"[Phase 2] Cannot read PC without halt: {e}")
    print("[Phase 2] Attempting monitor halt...")
end

monitor halt
python
import time
time.sleep(1)
end

# 读取关键寄存器
echo \n[Phase 2] === RISC-V CSR / Register Dump ===\n
info registers pc

python
pc_val = int(gdb.parse_and_eval("$pc"))
print(f"  PC = 0x{pc_val:016x}")

# 判断 PC 区域
if 0x00001000 <= pc_val <= 0x00001FFF:
    print("  [REGION] ZynqMP Boot ROM 区域 (不应在此)")
elif 0x00010000 <= pc_val <= 0x0001FFFF:
    print("  [REGION] Rocket BootROM / TLROM 区域")
elif 0x20000000 <= pc_val <= 0x2FFFFFFF:
    print("  [REGION] Boot flash 区域")
elif 0x80000000 <= pc_val <= 0x8FFFFFFF:
    print("  [REGION] DDR 区域 (OpenSBI/Linux 已跳入?)")
elif pc_val == 0:
    print("  [REGION] PC=0 — CPU reset state 或 debug 问题")
elif pc_val == 0xFFFFFFFF:
    print("  [REGION] PC=0xFFFFFFFF — 可能是读取失败")
else:
    print(f"  [REGION] 未知区域 0x{pc_val:016x}")
end

# 读取 mcause / mstatus / mie
python
try:
    mcause = gdb.parse_and_eval("$mcause")
    mstatus = gdb.parse_and_eval("$mstatus")
    mepc = gdb.parse_and_eval("$mepc")
    mtvec = gdb.parse_and_eval("$mtvec")
    print(f"  mcause  = 0x{int(mcause):016x}")
    print(f"  mstatus = 0x{int(mstatus):016x}")
    print(f"  mepc    = 0x{int(mepc):016x}")
    print(f"  mtvec   = 0x{int(mtvec):016x}")
except Exception as e:
    print(f"  [WARN] Cannot read CSRs: {e}")
end

# 读取 BootROM 范围 (Rocket TLROM)
echo \n[Phase 2] === BootROM 内容采样 ===\n
python
try:
    # 读取 BootROM 起始 4 个 word (Rocket 默认 BootROM = 0x00010000 或基于配置)
    # 实际 TLROM 地址从 Chipyard config 决定
    for addr in [0x00001000, 0x00010000, 0x00020000]:
        try:
            w = gdb.execute(f"x/4wx {hex(addr)}", to_string=True)
            print(f"  {hex(addr)}: {w.strip()}")
        except Exception as inner:
            print(f"  {hex(addr)}: read failed ({inner})")
except Exception as e:
    print(f"  [WARN]: {e}")
end

# 检查 BootROM 是否包含 sd_loader 魔数
# sd_loader_v0 BootROM 通常包含特定的 SD 初始化序列
echo \n[Phase 2] === BootROM 内容检查 ===\n
python
import struct
boot_rom_start = 0x00010000
try:
    # 读取 64 字节
    raw = []
    for i in range(0, 64, 4):
        w = int(gdb.parse_and_eval(f"*(unsigned int*)0x{boot_rom_start+i:08x}"))
        raw.append(w)
    words_str = " ".join(f"{w:08x}" for w in raw)
    print(f"  TLROM[0x10000..+63]: {words_str}")
    # 非零检查
    nonzero = sum(1 for w in raw if w != 0)
    print(f"  非零 word 数: {nonzero}/16")
    if nonzero == 0:
        print("  [WARN] 全为 0 — BootROM 未加载或地址错误")
    else:
        print("  [OK] BootROM 有内容")
except Exception as e:
    print(f"  BootROM read failed: {e}")
end

# 恢复运行 (不 halt 状态下退出)
echo \n[Phase 2] === Resuming CPU ===\n
monitor go

echo [Phase 2] Done. CPU restored to running state.\n
echo 请核对:\n
echo   1. PC 是否在 BootROM 范围 (0x10000 区域)?\n
echo   2. BootROM 内容是否非零?\n
echo   3. PC 是否等于已知 sd_loader 入口?\n
echo   4. mcause=0 (无异常)?\n

detach
quit 0
