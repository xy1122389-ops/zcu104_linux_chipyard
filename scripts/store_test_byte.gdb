# store_test_byte.gdb — test unaligned byte loop path only
set pagination off
set confirm off

target remote 172.19.128.1:2331
file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

printf "PC=0x%lx SP=0x%lx\n", $pc, $sp

set $memcpy = 0xffffffff8041e1d0
set $l2_flush = 0x2010200
set $src_va = 0xffffffff80200000
set $src_pa = 0x80400000
set $dst_va = 0xffffffff80e029e0
set $dst_pa = 0x810029e0

set $S_pc = $pc
# Use $x1 instead of $ra to avoid GDB frame save issue
set $S_x1 = $x1
set $S_a0 = $a0
set $S_a1 = $a1
set $S_a2 = $a2

# Zero 64 bytes of dst via SBA
set $i = 0
while $i < 8
  set *(unsigned long long *)($dst_pa + $i * 8) = 0
  set $i = $i + 1
end

# Flush L2 for zeroed dst
set *(unsigned long long *)$l2_flush = $dst_pa
set *(unsigned long long *)$l2_flush = $dst_pa + 64

printf "--- BYTE LOOP TEST: 64B unaligned ---\n"
flushregs
set $x1 = $S_pc
set $a0 = $dst_va
set $a1 = $src_va + 3
set $a2 = 64
set $pc = $memcpy
stepi 350

if $pc == $S_pc
  printf "PC OK (returned to 0x%lx)\n", $pc
else
  printf "PC WRONG: 0x%lx (expected 0x%lx)\n", $pc, $S_pc
end

# Flush L2 for dst
set *(unsigned long long *)$l2_flush = $dst_pa
set *(unsigned long long *)$l2_flush = $dst_pa + 64

# Verify 16 bytes inline
set $err = 0
set $i = 0
while $i < 16
  set $s = *(unsigned char *)($src_pa + 3 + $i)
  set $d = *(unsigned char *)($dst_pa + $i)
  if $s != $d
    printf "  ERR @%d: src=0x%02x dst=0x%02x\n", $i, $s, $d
    set $err = $err + 1
  end
  set $i = $i + 1
end
if $err == 0
  printf "First 16 bytes: MATCH\n"
end

set $s1 = $src_pa + 3
set $s2 = $src_pa + 67
set $d2 = $dst_pa + 64
dump binary memory /tmp/st_byte_src.bin $s1 $s2
dump binary memory /tmp/st_byte_dst.bin $dst_pa $d2

# Restore
set $pc = $S_pc
set $x1 = $S_x1
set $a0 = $S_a0
set $a1 = $S_a1
set $a2 = $S_a2

printf "Done. Verify: cmp /tmp/st_byte_src.bin /tmp/st_byte_dst.bin\n"
detach
quit
