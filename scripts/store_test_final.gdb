# store_test_final.gdb
# Uses known-mapped addresses: .text (R+X) for src, stack area (R+W) for dst
# SP=0xffffffff80e02de0 → PA=0x81002de0 (in L2[7]: R+W)

set pagination off
set confirm off

target remote 172.19.128.1:2331
file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

printf "=== STORE TEST (mapped addresses) ===\n"
printf "PC=0x%lx SP=0x%lx\n", $pc, $sp

set $memcpy = 0xffffffff8041e1d0
set $l2_flush = 0x2010200

# Save state
set $S_pc = $pc
set $S_ra = $ra
set $S_a0 = $a0
set $S_a1 = $a1
set $S_a2 = $a2
set $S_t6 = $t6

# Source: kernel .text (readable)
set $src_va = 0xffffffff80200000
set $src_pa = 0x80400000

# Dest: stack area below SP (writable)
# SP=0xffffffff80e02de0 → PA offset: va-0xffffffff80e00000 + 0x81000000 = 0x81002de0
# Use SP-1024 = 0xffffffff80e029e0 → PA 0x810029e0
set $dst_va = 0xffffffff80e029e0
set $dst_pa = 0x810029e0

printf "src VA=0x%lx PA=0x%lx\n", $src_va, $src_pa
printf "dst VA=0x%lx PA=0x%lx\n", $dst_va, $dst_pa

# ===== TEST 1: 128B aligned copy (ld/sd) =====
printf "\n--- TEST 1: 128B aligned (ld/sd path) ---\n"

set $pc = $memcpy
set $a0 = $dst_va
set $a1 = $src_va
set $a2 = 128
set $ra = $S_pc
stepi 60
if $pc == $S_pc
  printf "PC=0x%lx OK (returned correctly)\n", $pc
else
  printf "PC=0x%lx WRONG (expected 0x%lx)\n", $pc, $S_pc
end

# Flush L2 for dst
set *(unsigned long long *)$l2_flush = $dst_pa
set *(unsigned long long *)$l2_flush = $dst_pa + 64

# Verify inline: first 16 bytes
set $err1 = 0
set $i = 0
while $i < 16
  set $s = *(unsigned char *)($src_pa + $i)
  set $d = *(unsigned char *)($dst_pa + $i)
  if $s != $d
    printf "  ERR @%d: src=0x%02x dst=0x%02x\n", $i, $s, $d
    set $err1 = $err1 + 1
  end
  set $i = $i + 1
end
if $err1 == 0
  printf "  First 16 bytes: MATCH\n"
end

dump binary memory /tmp/st_final1_src.bin $src_pa ($src_pa + 128)
dump binary memory /tmp/st_final1_dst.bin $dst_pa ($dst_pa + 128)

# ===== TEST 2: 64B unaligned (byte loop) =====
printf "\n--- TEST 2: 64B unaligned (byte loop) ---\n"

# Zero 64 bytes of dst
set $i = 0
while $i < 8
  set *(unsigned long long *)($dst_pa + $i * 8) = 0
  set $i = $i + 1
end

set $pc = $memcpy
set $a0 = $dst_va
set $a1 = $src_va + 3
set $a2 = 64
set $ra = $S_pc
# 64 < 128 → tail path. src+3 mod 8 ≠ dst mod 8 → byte loop
# src+3: 0x...03, not 4-aligned → byte loop
# 4 insns × 64 + 6 setup = 262
stepi 280
if $pc == $S_pc
  printf "PC=0x%lx OK\n", $pc
else
  printf "PC=0x%lx WRONG (expected 0x%lx)\n", $pc, $S_pc
end

set *(unsigned long long *)$l2_flush = $dst_pa
set *(unsigned long long *)$l2_flush = $dst_pa + 64

set $err2 = 0
set $i = 0
while $i < 16
  set $s = *(unsigned char *)($src_pa + 3 + $i)
  set $d = *(unsigned char *)($dst_pa + $i)
  if $s != $d
    printf "  ERR @%d: src=0x%02x dst=0x%02x\n", $i, $s, $d
    set $err2 = $err2 + 1
  end
  set $i = $i + 1
end
if $err2 == 0
  printf "  First 16 bytes: MATCH\n"
end

dump binary memory /tmp/st_final2_src.bin ($src_pa + 3) ($src_pa + 67)
dump binary memory /tmp/st_final2_dst.bin $dst_pa ($dst_pa + 64)

# ===== TEST 3: 256B through address-aligned ld/sd =====
printf "\n--- TEST 3: 256B aligned ---\n"

set $pc = $memcpy
set $a0 = $dst_va
set $a1 = $src_va
set $a2 = 256
set $ra = $S_pc
# 256: 2 iterations of 128-byte loop = ~70×2 + ~10 = 150
stepi 160
if $pc == $S_pc
  printf "PC=0x%lx OK\n", $pc
else
  printf "PC=0x%lx WRONG (expected 0x%lx)\n", $pc, $S_pc
end

set *(unsigned long long *)$l2_flush = $dst_pa
set *(unsigned long long *)$l2_flush = $dst_pa + 64
set *(unsigned long long *)$l2_flush = $dst_pa + 128
set *(unsigned long long *)$l2_flush = $dst_pa + 192

dump binary memory /tmp/st_final3_src.bin $src_pa ($src_pa + 256)
dump binary memory /tmp/st_final3_dst.bin $dst_pa ($dst_pa + 256)

set $err3 = 0
set $i = 0
while $i < 32
  set $s = *(unsigned char *)($src_pa + $i)
  set $d = *(unsigned char *)($dst_pa + $i)
  if $s != $d
    printf "  ERR @%d: src=0x%02x dst=0x%02x\n", $i, $s, $d
    set $err3 = $err3 + 1
  end
  set $i = $i + 1
end
if $err3 == 0
  printf "  First 32 bytes: MATCH\n"
end

# ===== Restore =====
set $pc = $S_pc
set $ra = $S_ra
set $a0 = $S_a0
set $a1 = $S_a1
set $a2 = $S_a2
set $t6 = $S_t6
printf "\nRestored PC=0x%lx\n", $S_pc

printf "\n=== RESULTS ===\n"
printf "Test 1 errors: %d\n", $err1
printf "Test 2 errors: %d\n", $err2
printf "Test 3 errors: %d\n", $err3
printf "Full verify: cmp /tmp/st_final1_src.bin /tmp/st_final1_dst.bin && cmp /tmp/st_final2_src.bin /tmp/st_final2_dst.bin && cmp /tmp/st_final3_src.bin /tmp/st_final3_dst.bin && echo ALL_PASS\n"

detach
quit
