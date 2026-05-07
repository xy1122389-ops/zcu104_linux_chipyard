# read_ceva_version.gdb — 手动 GDB 会话：读 CEVA DM VERSION 0x65000004
#
# 用法（手动）:
#   riscv64-unknown-elf-gdb -q -batch \
#       -ex "target remote 127.0.0.1:3333" \
#       -x scripts/read_ceva_version.gdb
#
# 或加载后手动执行:
#   (gdb) target remote 127.0.0.1:3333
#   (gdb) source scripts/read_ceva_version.gdb

set remotetimeout 15
target remote 127.0.0.1:3333

monitor halt

echo \n=== CEVA DM VERSION Read (Phase 0B) ===\n

# 方法 1: 直接 SBA 读（不经过 CPU）
# 期望: 0x0B000500
x/1xw 0x65000004

# 方法 2: 用 printf 打印
set $ceva_ver = *(unsigned int *)0x65000004
printf "CEVA_VERSION @ 0x65000004 = 0x%08X\n", $ceva_ver

if ($ceva_ver == 0x0B000500)
  echo RESULT: PASS - CEVA DM VERSION OK\n
else
  echo RESULT: FAIL - unexpected value\n
end

monitor go
detach
quit
