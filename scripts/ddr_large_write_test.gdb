# ddr_large_write_test.gdb — DDR 大数据写入完整性实验
#
# 目的: 验证并解决 SBA（J-Link JTAG系统总线）大块写入 DDR 后数据不可信问题
#   - SBA 写入会在 L2 InclusiveCache 创建 clean 行
#   - clean 行被 evict 时不写回 DDR → 数据丢失
#   - 修复方案: 写后立即运行 CPU ld+sd loop 将所有 L2 行标记为 dirty
#
# 实验分三阶段:
#   Phase A: SBA 写入 → 立即验证 (L2 hit, 应通过)
#   Phase B: SBA 写 EVICT_BASE 充满 L2 → 再验证 TEST_BASE (SBA 写是否到达 DDR)
#   Phase C: SBA 写 + CPU ld+sd copyback → SBA eviction → 验证 (修复后应通过)
#
# DDR 布局:
#   0x8C000000 - 0x8C100000  测试数据区 (1MB)
#   0x8D000000 - 0x8D400000  L2 eviction 缓冲区 (4MB)
#   0x81200000               CPU 辅助代码 (copyback loop)
#
# 关键: CPU 循环使用 GDB 脚本级别 hbreak+continue (同 linux_boot.gdb Phase 3)
#       NOT Python gdb.execute("continue") — 那会阻塞无法返回
#
# 使用方法:
#   JLINK_HOST=127.0.0.1 JLINK_PORT=3333 \
#   riscv64-unknown-elf-gdb --batch -x scripts/ddr_large_write_test.gdb

set pagination off
set confirm off
set remotetimeout 300

# ============================================================
# 连接并初始化
# ============================================================
python
import os, gdb, struct, time

JLINK_HOST = os.environ.get("JLINK_HOST", "127.0.0.1")
JLINK_PORT = int(os.environ.get("JLINK_PORT", "3333"))

gdb.write(f"\n[ddr_large_write_test] Connecting to {JLINK_HOST}:{JLINK_PORT}\n")
last_err = None
for attempt in range(1, 4):
    try:
        gdb.execute(f"target remote {JLINK_HOST}:{JLINK_PORT}")
        gdb.write(f"[info] Connected on attempt {attempt}\n")
        last_err = None
        break
    except gdb.error as e:
        last_err = e
        gdb.write(f"[warn] attempt {attempt} failed: {e}\n")
        if attempt < 3:
            time.sleep(2)
if last_err:
    raise last_err
end

monitor halt
python
import time
time.sleep(0.5)
end

# CPU 初始化 (与 linux_boot.gdb 保持一致)
monitor WriteCSR 0x180 0
monitor WriteCSR 0x300 0x1800
monitor WriteCSR 0x7b0 0x4000F0C3
echo [info] CPU initialized: satp=0, dcsr=0x4000F0C3\n

# ============================================================
# 安装 CPU copyback loop 到 0x81200000
# 指令: ld t0,0(a0); sd t0,0(a0); addi a0,a0,8; blt a0,a1,-12; c.ebreak
# hbreak 地址: 0x81200010 (c.ebreak 所在)
# ============================================================
echo \n[setup] Installing CPU copyback loop at 0x81200000\n
set *(unsigned int*)0x81200000 = 0x00053283
set *(unsigned int*)0x81200004 = 0x00553023
set *(unsigned int*)0x81200008 = 0x00850513
set *(unsigned int*)0x8120000C = 0xFEB54AE3
set *(unsigned short*)0x81200010 = 0x9002

python
code = [
    (0x81200000, 0x00053283, "ld t0,0(a0)"),
    (0x81200004, 0x00553023, "sd t0,0(a0)"),
    (0x81200008, 0x00850513, "addi a0,a0,8"),
    (0x8120000C, 0xFEB54AE3, "blt a0,a1,-12"),
]
ok = sum(1 for a, e, n in code if (int(gdb.parse_and_eval(f"*(unsigned int*)0x{a:x}")) & 0xFFFFFFFF) == e)
cebreak = int(gdb.parse_and_eval("*(unsigned short*)0x81200010")) & 0xFFFF
if cebreak == 0x9002:
    ok += 1
gdb.write(f"  [ok] copyback loop: {ok}/5 verified\n")

# 全局状态
TEST_BASE  = 0x8C000000
TEST_END   = 0x8C100000
TEST_SIZE  = TEST_END - TEST_BASE
EVICT_BASE = 0x8D000000
EVICT_END  = 0x8D400000
EVICT_SIZE = EVICT_END - EVICT_BASE
MAGIC_A = 0xDEADBEEFCAFEBABE
MAGIC_B = 0x0123456789ABCDEF

def expected_pattern(addr):
    word_idx = (addr - TEST_BASE) // 8
    return ((MAGIC_A + word_idx * MAGIC_B) ^ (addr & 0xFFFFFFFFFFFFFFFF)) & 0xFFFFFFFFFFFFFFFF

def sba_read64(addr):
    return int(gdb.parse_and_eval(f"*(unsigned long long*)0x{addr:x}")) & 0xFFFFFFFFFFFFFFFF

def spot_verify(label, count=64):
    step = TEST_SIZE // count
    passed, failed = 0, 0
    first_fail = None
    fails = []
    for i in range(count):
        addr = TEST_BASE + i * step
        got = sba_read64(addr)
        exp = expected_pattern(addr)
        if got == exp:
            passed += 1
        else:
            failed += 1
            fails.append((addr, exp, got))
            if first_fail is None:
                first_fail = (addr, exp, got)
    gdb.write(f"  [{label}] 验证 {count} 点: PASS={passed}, FAIL={failed}\n")
    if failed > 0:
        a, e, g2 = first_fail
        gdb.write(f"  [{label}] 首次不匹配: addr=0x{a:08x} exp=0x{e:016x} got=0x{g2:016x}\n")
        for fa, fe, fg in fails[:3]:
            zero_mark = " ← ZERO!" if fg == 0 else ""
            gdb.write(f"  [{label}]   0x{fa:08x}: exp=0x{fe:016x} got=0x{fg:016x}{zero_mark}\n")
    return passed, failed

import builtins
builtins._G = {
    'TEST_BASE': TEST_BASE, 'TEST_END': TEST_END, 'TEST_SIZE': TEST_SIZE,
    'EVICT_BASE': EVICT_BASE, 'EVICT_END': EVICT_END, 'EVICT_SIZE': EVICT_SIZE,
    'expected_pattern': expected_pattern,
    'sba_read64': sba_read64,
    'spot_verify': spot_verify,
}
gdb.write("[ok] Global state initialized\n")
end

# ============================================================
# Phase A: SBA 写入 + 立即验证
# ============================================================
python
import struct, time
G = __builtins__._G

gdb.write("\n" + "="*60 + "\n")
gdb.write("Phase A: SBA 写入 + 立即验证 (pre-eviction, L2 hit)\n")
gdb.write("="*60 + "\n")

# 生成并写入 test pattern
pat_data = bytearray(G['TEST_SIZE'])
for i in range(G['TEST_SIZE'] // 8):
    addr = G['TEST_BASE'] + i * 8
    struct.pack_into('<Q', pat_data, i * 8, G['expected_pattern'](addr))
pat_file = "/tmp/ddr_test_pat_1mb.bin"
with open(pat_file, 'wb') as f:
    f.write(pat_data)
G['pat_file'] = pat_file

gdb.write(f"  [A1] 生成 {G['TEST_SIZE']//1024}KB pattern, SBA 写入 0x{G['TEST_BASE']:08x}...\n")
t0 = time.time()
gdb.execute(f"restore {pat_file} binary 0x{G['TEST_BASE']:x}")
elapsed = time.time() - t0
gdb.write(f"  [A1] SBA 完成: {elapsed:.1f}s ({G['TEST_SIZE']/1024/elapsed:.1f} KB/s)\n")

pa_pass, pa_fail = G['spot_verify']("A2", count=64)
G['pa_pass'] = pa_pass
G['pa_fail'] = pa_fail
gdb.write(f"  Phase A: {'PASS ✓' if pa_fail == 0 else 'FAIL ✗'}\n")
end

# ============================================================
# Phase B: SBA 写 EVICT_BASE 充满 L2 → 验证 TEST_BASE
# 不需要 CPU 循环: SBA 写 4MB 溢出 L2 使 TEST_BASE clean lines 被 evict
# ============================================================
python
import time
G = __builtins__._G

gdb.write("\n" + "="*60 + "\n")
gdb.write("Phase B: SBA 写 EVICT_BASE 充满 L2 → 验证 TEST_BASE\n")
gdb.write("="*60 + "\n")
gdb.write(f"  eviction: SBA 写 {G['EVICT_SIZE']//1024}KB 到 0x{G['EVICT_BASE']:08x}\n")

evict_file = "/tmp/ddr_evict_4mb.bin"
with open(evict_file, 'wb') as f:
    f.write(bytes([0xAA] * G['EVICT_SIZE']))

t0 = time.time()
gdb.execute(f"restore {evict_file} binary 0x{G['EVICT_BASE']:x}")
elapsed = time.time() - t0
gdb.write(f"  [B1] EVICT SBA 完成: {elapsed:.1f}s ({G['EVICT_SIZE']/1024/elapsed:.1f} KB/s)\n")

pb_pass, pb_fail = G['spot_verify']("B2", count=64)
G['pb_pass'] = pb_pass
G['pb_fail'] = pb_fail
sba_reliable = (pb_fail == 0)
G['sba_reliable'] = sba_reliable
if pb_fail == 0:
    gdb.write("  Phase B: PASS ✓ (SBA 数据在 L2 eviction 后仍正确)\n")
    gdb.write("  INFO: SBA 写入直接到达 DDR, 无 clean-evict 丢失问题\n")
else:
    gdb.write("  Phase B: FAIL ✗ — SBA 数据在 L2 eviction 后丢失!\n")
    gdb.write("  *** 证实: SBA 写入只存于 L2 clean lines, evict 时不写回 DDR ***\n")
end

# ============================================================
# Phase C: SBA 写 + CPU copyback → SBA eviction → 验证
# 关键: CPU copyback 在 GDB 脚本级别执行 (hbreak + continue)
# ============================================================
python
import time
G = __builtins__._G

gdb.write("\n" + "="*60 + "\n")
gdb.write("Phase C: SBA 写 + CPU copyback → SBA eviction → 验证\n")
gdb.write("="*60 + "\n")

# C1: 重新 SBA 写入 TEST_BASE
gdb.write(f"  [C1] 重新 SBA 写入 TEST_BASE...\n")
t0 = time.time()
gdb.execute(f"restore {G['pat_file']} binary 0x{G['TEST_BASE']:x}")
elapsed = time.time() - t0
gdb.write(f"  [C1] SBA 完成: {elapsed:.1f}s\n")

# C2: 配置 CPU copyback loop 参数 (CPU 执行本身在 GDB script 级别)
gdb.write(f"  [C2] 配置 CPU copyback: a0=0x{G['TEST_BASE']:08x}, a1=0x{G['TEST_END']:08x}\n")
gdb.execute(f"set $a0 = 0x{G['TEST_BASE']:x}")
gdb.execute(f"set $a1 = 0x{G['TEST_END']:x}")
gdb.execute(f"set $pc = 0x81200000")
gdb.execute("monitor WriteCSR 0x7b0 0x4000F0C3")
gdb.write("  [C2] CPU 配置完成 → 执行 hbreak+continue (GDB script level)...\n")
end

# GDB 脚本级别执行 copyback loop (与 linux_boot.gdb Phase 3 一致)
delete breakpoints
hbreak *0x81200010
echo [C2] CPU copyback loop running (ld+sd 1MB)...\n
continue
echo [C2] CPU copyback loop done\n
delete breakpoints

python
import time
G = __builtins__._G

cur_pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
cur_a0 = int(gdb.parse_and_eval("$a0")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"  [C2] Stopped at PC=0x{cur_pc:016x}, a0=0x{cur_a0:016x}\n")
if cur_a0 != G['TEST_END']:
    gdb.write(f"  [WARN] a0 (0x{cur_a0:08x}) != TEST_END (0x{G['TEST_END']:08x}) — loop incomplete?\n")
else:
    gdb.write(f"  [C2] copyback loop completed: a0 == TEST_END ✓\n")

# C3: SBA 写 EVICT_BASE 溢出 L2 (dirty TEST_BASE lines writeback → DDR)
evict_file = "/tmp/ddr_evict_4mb.bin"
gdb.write(f"  [C3] SBA eviction (写 {G['EVICT_SIZE']//1024}KB 到 EVICT_BASE)...\n")
t0 = time.time()
gdb.execute(f"restore {evict_file} binary 0x{G['EVICT_BASE']:x}")
elapsed = time.time() - t0
gdb.write(f"  [C3] eviction SBA 完成: {elapsed:.1f}s\n")

# C4: 验证 TEST_BASE
pc_pass, pc_fail = G['spot_verify']("C4", count=64)
G['pc_pass'] = pc_pass
G['pc_fail'] = pc_fail
copyback_reliable = (pc_fail == 0)
G['copyback_reliable'] = copyback_reliable
if pc_fail == 0:
    gdb.write("  Phase C: PASS ✓ (CPU copyback 后数据在 L2 eviction 后仍正确)\n")
else:
    gdb.write("  Phase C: FAIL ✗\n")
end

# ============================================================
# 最终报告
# ============================================================
python
G = __builtins__._G

gdb.write("\n" + "="*60 + "\n")
gdb.write("=== DDR 大数据写入完整性实验 — 最终报告 ===\n")
gdb.write("="*60 + "\n")
gdb.write(f"  TEST  (1MB): 0x{G['TEST_BASE']:08x} - 0x{G['TEST_END']:08x}\n")
gdb.write(f"  EVICT (4MB): 0x{G['EVICT_BASE']:08x} - 0x{G['EVICT_END']:08x}\n")
gdb.write(f"  CPU copyback: 0x81200000 (ld+sd loop, hbreak at 0x81200010)\n")
gdb.write("\n")

def rs(fail): return "PASS ✓" if fail == 0 else "FAIL ✗"
gdb.write(f"  Phase A (SBA写 → 立即验证):                   {rs(G['pa_fail'])} ({G['pa_pass']}/64)\n")
gdb.write(f"  Phase B (SBA写 → SBA 4MB evict → 验证):       {rs(G['pb_fail'])} ({G['pb_pass']}/64)\n")
gdb.write(f"  Phase C (SBA写+CPU copyback → SBA evict → 验证): {rs(G['pc_fail'])} ({G['pc_pass']}/64)\n")
gdb.write("\n")

pa, pb, pc_ = G['pa_fail'], G['pb_fail'], G['pc_fail']
if pa > 0:
    gdb.write("  结论: SBA 写入基本功能异常 — Phase A 失败\n")
elif pb > 0 and pc_ == 0:
    gdb.write("  结论: SBA 写入 UNSAFE, CPU copyback SAFE\n")
    gdb.write("        → 每次 SBA 大块写入后必须运行 CPU ld+sd copyback loop\n")
    gdb.write("        → linux_boot.gdb Phase 3 L2 invalidation 提供等效保护\n")
elif pb == 0:
    gdb.write("  结论: SBA 写入 SAFE — 数据直接写入 DDR, 不受 L2 eviction 影响\n")
elif pb > 0 and pc_ > 0:
    gdb.write("  结论: 异常 — Phase B 和 C 都失败\n")
    gdb.write("        可能原因: DDR 不稳定, fence 缺失, copyback loop 未完成\n")

gdb.write("="*60 + "\n")
gdb.write("\n[done] 实验完成\n")
end

disconnect
quit
