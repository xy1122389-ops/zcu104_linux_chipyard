# phase4_check_opensbi_linux.gdb
#
# Phase 4: 让 Rocket 跳入 OpenSBI/Linux，通过 PC 和 klog 判断是否进入 Linux
#
# 策略 (保守):
#   1. halt Rocket，读取当前 PC
#   2. 如果 PC 在 DDR (0x80000000+) → OpenSBI 已经启动
#   3. 如果 PC 仍在 BootROM → 让它运行直到跳入 DDR
#   4. 运行 60 秒
#   5. halt + 读取 PC / stage_mark / klog 指针
#
# 成功标准:
#   PC = 0x80000000 范围 (OpenSBI/Linux 代码)
#   stage_mark @ 0x8F000000 非零
#   klog 有 "Linux version" 或 "OpenSBI"
#
# 注意: 不 restore payload，payload 必须已由 sd_loader 加载 (Phase 3 通过后)

set pagination off
set confirm off
set remotetimeout 30

python
import os, time
host = os.environ.get("JLINK_HOST", "127.0.0.1")
port = os.environ.get("JLINK_PORT", "3333")
gdb.execute(f"target remote {host}:{port}")
print(f"[Phase 4] Connected to J-Link at {host}:{port}")
end

# --- 初始状态快照 ---
monitor halt
python
import time
time.sleep(1)
pc = int(gdb.parse_and_eval("$pc"))
print(f"[Phase 4] PC on initial halt = 0x{pc:016x}")

if 0x80000000 <= pc <= 0x8FFFFFFF:
    print("  [INFO] PC already in DDR — OpenSBI/Linux may be running or about to start")
elif 0x00010000 <= pc <= 0x0001FFFF:
    print("  [INFO] PC in BootROM — sd_loader may still be loading (or hasn't jumped yet)")
    print("         Resuming and waiting 30 more seconds for sd_loader to complete...")
end

# 运行直到 sd_loader 跳入 DDR (最多等 30s 更多)
echo [Phase 4] Resuming CPU for up to 30s to allow sd_loader to complete loading...\n
monitor go
python
import time
time.sleep(30)
end
monitor halt
python
import time
time.sleep(1)
pc = int(gdb.parse_and_eval("$pc"))
print(f"[Phase 4] PC after 30s additional run = 0x{pc:016x}")
if 0x80000000 <= pc <= 0x8FFFFFFF:
    print("  [OK] PC now in DDR range — OpenSBI/Linux is running!")
else:
    print(f"  [INFO] PC=0x{pc:016x} — may still be loading or stuck")
end

# --- 让 OpenSBI/Linux 运行 60 秒 ---
python
run_secs = int(os.environ.get("PHASE4_RUN_SECS", "60"))
print(f"\n[Phase 4] Resuming CPU for {run_secs}s to let Linux boot...")
end
monitor go
python
import time
run_secs = int(os.environ.get("PHASE4_RUN_SECS", "60"))
print(f"[Phase 4] CPU running for {run_secs}s...")
time.sleep(run_secs)
print("[Phase 4] Halting now...")
end
monitor halt
python
import time
time.sleep(1)
end

# --- 状态读取 ---
echo \n[Phase 4] === Final State Check ===\n
python
try:
    pc = int(gdb.parse_and_eval("$pc"))
    print(f"  Final PC = 0x{pc:016x}")
    
    if 0xffffffff80000000 <= pc:  # kernel virtual address
        print("  [OK] PC in kernel virtual address space → Linux is running!")
    elif 0x80200000 <= pc <= 0x8FFFFFFF:
        print("  [OK] PC in OpenSBI/Linux PA range")
    elif 0x80000000 <= pc <= 0x801FFFFF:
        print("  [INFO] PC in OpenSBI protected range (PMP)")
    else:
        print(f"  [INFO] PC = 0x{pc:016x} — check region")
    
    # mcause / mstatus
    try:
        mcause = int(gdb.parse_and_eval("$mcause"))
        mstatus = int(gdb.parse_and_eval("$mstatus"))
        print(f"  mcause = 0x{mcause:016x}")
        print(f"  mstatus = 0x{mstatus:016x}")
        priv = (mstatus >> 11) & 3
        priv_names = {0: "User", 1: "Supervisor", 3: "Machine"}
        print(f"  MPP = {priv_names.get(priv, 'Unknown')} ({priv})")
    except Exception as e:
        print(f"  CSR read failed: {e}")
except Exception as e:
    print(f"  PC read failed: {e}")
end

# --- stage_mark 检查 (0x8F000000) ---
echo \n[Phase 4] === stage_mark @ 0x8F000000 ===\n
python
try:
    # stage_mark 是 /init 写入的魔数，标志 /init 是否执行
    w0 = int(gdb.parse_and_eval("*(unsigned long long*)0x8F000000"))
    print(f"  stage_mark[0] = 0x{w0:016x}")
    
    if w0 == 0:
        print("  [INFO] stage_mark=0 — /init 尚未执行 (或 Linux 未到 userspace)")
    elif w0 == 0x5A435531494E4954:
        print("  [OK] stage_mark = 'ZCU1INIT' — /init has run!")
    else:
        # 尝试解码为 ASCII
        tag = w0 >> 32
        sub = w0 & 0xFFFFFFFF
        tag_bytes = tag.to_bytes(4, 'big')
        try:
            tag_str = tag_bytes.decode('ascii', errors='replace')
        except:
            tag_str = "????"
        print(f"  stage_mark = tag={tag_str}(0x{tag:08x}) sub=0x{sub:08x}")
        if w0 != 0:
            print("  [OK] stage_mark is non-zero — some progress made!")
except Exception as e:
    print(f"  stage_mark read failed: {e}")
end

# --- klog 指针检查 (无 vmlinux, 只检查已知 PA) ---
echo \n[Phase 4] === klog sanity check @ __log_buf PA ===\n
python
# linux-clean __log_buf PA = 0x80ecf060 (从 vmlinux VA→PA 计算)
# 如果内核编译变了这个值会不同，但可以用基本 sanity 检查
LOG_BUF_PA = 0x80ecf060  # VA = 0xffffffff80ecf060, PA = VA + 0x100200000 mod 2^64

try:
    # 读取 __log_buf 开头，看是否有 printk 内容
    data = b""
    for i in range(0, 128, 4):
        w = int(gdb.parse_and_eval(f"*(unsigned int*)0x{LOG_BUF_PA+i:08x}"))
        data += w.to_bytes(4, 'little')
    
    printable = bytes(b if 32 <= b < 127 else ord('.') for b in data)
    print(f"  __log_buf[0..127]: {printable.decode('ascii', errors='replace')[:80]}")
    
    nonzero = sum(1 for b in data if b != 0)
    if nonzero > 0:
        print(f"  [OK] klog has {nonzero} non-zero bytes — printk is running!")
    else:
        print(f"  [INFO] klog all zeros — Linux may not have reached printk init")
        
    # 检查 "Linux version" 或 "OpenSBI"
    text = printable.decode('ascii', errors='replace')
    if 'Linux' in text or 'OpenSBI' in text or 'RISC-V' in text:
        print(f"  [OK] Found kernel marker text!")
    
except Exception as e:
    print(f"  klog read failed (PA may be wrong for this build): {e}")
    print(f"  Trying alternate PA 0x80edc190...")
    try:
        w = int(gdb.parse_and_eval("*(unsigned int*)0x80edc190"))
        print(f"  __log_buf[0x80edc190] = 0x{w:08x}")
    except Exception as e2:
        print(f"  Also failed: {e2}")
end

# 恢复运行
echo \n[Phase 4] Restoring CPU to running state...\n
monitor go

echo [Phase 4] Done.\n
echo 请核对:\n
echo   PASS 标准:\n
echo     1. Final PC 在 kernel VA (0xffffffff8xxxxxxx) 或 DDR PA (0x80200000+)\n
echo     2. stage_mark @ 0x8F000000 非零 (如果 /init 运行)\n
echo     3. klog 有 'Linux version' 或 'OpenSBI'\n
echo   如果全部通过 → 继续 Phase 5 (SW6 切回 SD boot 全自动测试)\n

detach
quit 0
