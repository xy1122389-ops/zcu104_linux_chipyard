# phase3_check_ddr_payload.gdb
#
# Phase 3: 让 sd_loader_v0 从 SD p2 读取 manifest/payload/DTB
#           然后只读检查 DDR 内容，不跳转执行
#
# sd_loader_v0 加载地址:
#   fw_payload → 0x80000000
#   DTB        → 0x84000000
#
# 策略:
#   1. 用 monitor halt 停住 Rocket
#   2. 等待 sd_loader 有机会运行 (让它运行 N 秒)
#   3. 再次 halt
#   4. 只读检查 0x80000000 和 0x84000000
#
# 如果 Rocket 还在 BootROM 没有开始加载:
#   可能需要先等一段时间让 sd_loader 执行
#
# 运行方式:
#   bash scripts/phase3_check_ddr_payload.sh

set pagination off
set confirm off
set remotetimeout 30

python
import os, time
host = os.environ.get("JLINK_HOST", "127.0.0.1")
port = os.environ.get("JLINK_PORT", "3333")
gdb.execute(f"target remote {host}:{port}")
print(f"[Phase 3] Connected to J-Link at {host}:{port}")
end

# 先检查当前 PC
monitor halt
python
import time
time.sleep(1)
pc = int(gdb.parse_and_eval("$pc"))
print(f"[Phase 3] Current PC on halt = 0x{pc:016x}")

if 0x80000000 <= pc <= 0x8FFFFFFF:
    print("  [INFO] PC in DDR — sd_loader may have already jumped to OpenSBI!")
    print("  [INFO] Checking 0x80000000 content now...")
elif 0x00010000 <= pc <= 0x0001FFFF:
    print("  [INFO] PC in BootROM range — sd_loader is running or waiting")
elif pc == 0:
    print("  [WARN] PC=0 — potential debug/reset issue")
else:
    print(f"  [INFO] PC=0x{pc:016x}")
end

# 让 Rocket 运行 15 秒 (给 sd_loader 时间加载 ~50MB payload)
echo \n[Phase 3] Resuming Rocket for 15s to allow sd_loader to load from SD...\n
monitor go
python
import time
print("[Phase 3] CPU running... waiting 15s for sd_loader to read SD card")
time.sleep(15)
print("[Phase 3] Halting...")
end
monitor halt
python
import time
time.sleep(1)
pc = int(gdb.parse_and_eval("$pc"))
print(f"[Phase 3] PC after 15s run = 0x{pc:016x}")
end

# ★ 只读检查 DDR 内容
echo \n[Phase 3] === DDR Content Check (READ-ONLY) ===\n

python
import struct

def read_ddr_region(addr, label, expected_magic=None):
    print(f"\n  --- {label} @ 0x{addr:08x} ---")
    try:
        words = []
        for i in range(0, 16, 4):
            w = int(gdb.parse_and_eval(f"*(unsigned int*)0x{addr+i:08x}"))
            words.append(w)
        hex_str = " ".join(f"{w:08x}" for w in words)
        print(f"  [0x{addr:08x}] {hex_str}")
        
        # 非零检查
        nonzero = sum(1 for w in words if w != 0)
        if nonzero == 0:
            print(f"  [FAIL] 全为 0 — payload 未加载或 DDR 未初始化")
            return False
        
        # RISC-V ELF / OpenSBI 魔数检查
        w0 = words[0]
        if w0 == 0x7f454c46:  # ELF magic
            print(f"  [OK] ELF magic detected (0x7F454C46)")
        elif w0 == 0x6f0000ef or w0 == 0xef000017:  # JAL 指令 (OpenSBI 入口)
            print(f"  [OK] RISC-V JAL instruction at entry (OpenSBI)")
        elif expected_magic and w0 == expected_magic:
            print(f"  [OK] Expected magic 0x{expected_magic:08x} found")
        else:
            print(f"  [INFO] First word = 0x{w0:08x} (not ELF/JAL — may still be valid code)")
        
        print(f"  非零 word 数: {nonzero}/4")
        return True
    except Exception as e:
        print(f"  [ERROR] Read failed: {e}")
        return False

# fw_payload 检查 (OpenSBI 入口)
fw_ok = read_ddr_region(0x80000000, "fw_payload @ 0x80000000 (OpenSBI entry)")

# fw_payload 末尾检查 (确认完整加载, ~50MB 之后)
read_ddr_region(0x82000000, "fw_payload + 0x2000000 (mid-range sanity)")

# DTB 检查
print("\n  --- DTB @ 0x84000000 ---")
try:
    w0 = int(gdb.parse_and_eval("*(unsigned int*)0x84000000"))
    w1 = int(gdb.parse_and_eval("*(unsigned int*)0x84000004"))
    w2 = int(gdb.parse_and_eval("*(unsigned int*)0x84000008"))
    print(f"  [0x84000000] {w0:08x} {w1:08x} {w2:08x}")
    if w0 == 0xd00dfeed:
        print(f"  [OK] DTB magic 0xD00DFEED detected!")
    elif w0 == 0xedfe0dd0:
        print(f"  [OK] DTB FDT_MAGIC (LE) 0xEDFE0DD0 detected!")
    elif w0 == 0:
        print(f"  [FAIL] DTB location all zeros — not loaded yet")
    else:
        print(f"  [INFO] First word = 0x{w0:08x} (non-zero, check manually)")
except Exception as e:
    print(f"  [ERROR] DTB read failed: {e}")

# 结果摘要
print(f"\n[Phase 3] Summary:")
if fw_ok:
    print("  fw_payload @ 0x80000000: PRESENT (non-zero)")
else:
    print("  fw_payload @ 0x80000000: NOT LOADED")
end

# 继续让 CPU 运行 (如果 payload 已加载，可能 Rocket 要跳转)
echo \n[Phase 3] Restoring CPU to running state...\n
monitor go

echo [Phase 3] Done.\n
echo 请核对:\n
echo   1. 0x80000000 非零 + OpenSBI magic?\n
echo   2. 0x84000000 = 0xD00DFEED (DTB magic)?\n
echo   3. 如果两者都非零 → Phase 4 可以进行\n
echo   4. 如果都为零 → sd_loader 未运行 → 检查 BootROM 和 SD p2 内容\n

detach
quit 0
