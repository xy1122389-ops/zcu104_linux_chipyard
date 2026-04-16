# store_test_stepi.gdb
# Uses stepi N to step through memcpy (no hbreak needed)
# Interrupts are already disabled (MIE=0, SIE=0)
# Uses proper writable memory for dst

set pagination off
set confirm off

target remote 172.19.128.1:2331
file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

printf "=== Store Test (stepi) ===\n"
printf "PC=0x%lx\n", $pc

set $memcpy_va = 0xffffffff8041e1d0
set $src_pa    = 0x82F01000
set $src_va    = 0xFFFFFFFF82D01000
set $dst_pa    = 0x82F02000
set $dst_va    = 0xFFFFFFFF82D02000
set $l2_flush  = 0x2010200

# Save state
set $S_pc  = $pc
set $S_ra  = $ra
set $S_a0  = $a0
set $S_a1  = $a1
set $S_a2  = $a2
set $S_t6  = $t6

# Load source via SBA
restore /tmp/store_test_pattern.bin binary 0x82F01000 0 2048
printf "Source loaded\n"

# Flush L2 for source (so CPU sees fresh data)
set $f = 0
while $f < 2048
  set *(unsigned long long *)$l2_flush = $src_pa + $f
  set $f = $f + 64
end

# ===== TEST A: Aligned 128B copy (ld/sd path, fast stepi) =====
printf "\n--- TEST A: aligned 128B ---\n"

# Zero dst
restore /tmp/zeros_2k.bin binary 0x82F02000 0 128
set $f = 0
while $f < 128
  set *(unsigned long long *)$l2_flush = $dst_pa + $f
  set $f = $f + 64
end

set $pc = $memcpy_va
set $a0 = $dst_va
set $a1 = $src_va
set $a2 = 128
set $ra = $S_pc
# Aligned 128B: mv+sltiu+branch(not taken)+andi+andi+beq(taken, both 0 mod 8)+andi+beqz(taken)
# Main loop: 1 iteration of 128-byte loop = ~32 insns + branch back = ~34
# Then tail: beqz a2 (a2=0) → ret
# Total: ~8 setup + 34 main + 2 tail = ~44 insns
stepi 50
printf "A: PC=0x%lx (expect save_pc=0x%lx)\n", $pc, $S_pc

# Flush L2 for dst, then SBA dump
set $f = 0
while $f < 128
  set *(unsigned long long *)$l2_flush = $dst_pa + $f
  set $f = $f + 64
end
dump binary memory /tmp/st_A_dst.bin $dst_pa ($dst_pa + 128)
dump binary memory /tmp/st_A_src.bin $src_pa ($src_pa + 128)
printf "A: dumped\n"

# ===== TEST B: Aligned 2048B copy (many ld/sd iterations) =====
printf "\n--- TEST B: aligned 2048B ---\n"

restore /tmp/zeros_2k.bin binary 0x82F02000 0 2048
set $f = 0
while $f < 2048
  set *(unsigned long long *)$l2_flush = $dst_pa + $f
  set $f = $f + 64
end

set $pc = $memcpy_va
set $a0 = $dst_va
set $a1 = $src_va
set $a2 = 2048
set $ra = $S_pc
# 2048/128 = 16 iterations of main loop
# Each iteration: 32 ld/sd + branch = ~33 insns
# Setup: 8, cleanup: 2
# Total: ~8 + 16*33 + 2 = 538
stepi 600
printf "B: PC=0x%lx (expect save_pc=0x%lx)\n", $pc, $S_pc

set $f = 0
while $f < 2048
  set *(unsigned long long *)$l2_flush = $dst_pa + $f
  set $f = $f + 64
end
dump binary memory /tmp/st_B_dst.bin $dst_pa ($dst_pa + 2048)
dump binary memory /tmp/st_B_src.bin $src_pa ($src_pa + 2048)
printf "B: dumped\n"

# ===== TEST C: Unaligned 127B copy (byte loop path) =====
printf "\n--- TEST C: unaligned 127B (byte loop) ---\n"

restore /tmp/zeros_2k.bin binary 0x82F02000 0 128
set $f = 0
while $f < 128
  set *(unsigned long long *)$l2_flush = $dst_pa + $f
  set $f = $f + 64
end

set $pc = $memcpy_va
set $a0 = $dst_va
set $a1 = $src_va + 1
set $a2 = 127
set $ra = $S_pc
# Unaligned: src%8=1, dst%8=0 → different → jump to tail
# Tail: 127 < 128 → already at small path
# src, dst, end: check 4-align: src+1 is NOT 4-aligned → byte loop
# Byte loop: 4 insns × 127 + branch + ret = ~512
# Setup: 4 insns to reach byte loop
# Total: ~516
stepi 600
printf "C: PC=0x%lx (expect save_pc=0x%lx)\n", $pc, $S_pc

set $f = 0
while $f < 128
  set *(unsigned long long *)$l2_flush = $dst_pa + $f
  set $f = $f + 64
end
dump binary memory /tmp/st_C_dst.bin $dst_pa ($dst_pa + 127)
dump binary memory /tmp/st_C_src.bin ($src_pa + 1) ($src_pa + 128)
printf "C: dumped\n"

# ===== TEST D: Unaligned 2047B (full byte loop stress) =====
printf "\n--- TEST D: unaligned 2047B ---\n"

restore /tmp/zeros_2k.bin binary 0x82F02000 0 2048
set $f = 0
while $f < 2048
  set *(unsigned long long *)$l2_flush = $dst_pa + $f
  set $f = $f + 64
end

set $pc = $memcpy_va
set $a0 = $dst_va
set $a1 = $src_va + 1
set $a2 = 2047
set $ra = $S_pc
# Byte loop: 4 insns × 2047 = 8188 + setup ~6 = 8194
stepi 8300
printf "D: PC=0x%lx (expect save_pc=0x%lx)\n", $pc, $S_pc

set $f = 0
while $f < 2048
  set *(unsigned long long *)$l2_flush = $dst_pa + $f
  set $f = $f + 64
end
dump binary memory /tmp/st_D_dst.bin $dst_pa ($dst_pa + 2047)
dump binary memory /tmp/st_D_src.bin ($src_pa + 1) ($src_pa + 2048)
printf "D: dumped\n"

# ===== Restore =====
set $pc  = $S_pc
set $ra  = $S_ra
set $a0  = $S_a0
set $a1  = $S_a1
set $a2  = $S_a2
set $t6  = $S_t6
printf "\nRestored. PC=0x%lx\n", $S_pc
printf "Verify: python3 /tmp/store_test_verify_stepi.py\n"

detach
quit
