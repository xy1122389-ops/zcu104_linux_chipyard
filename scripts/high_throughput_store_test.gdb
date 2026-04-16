# high_throughput_store_test.gdb
# Tests if rapid memcpy through Sv39 MMU causes data corruption
# Uses the halted kernel's S-mode MMU context
#
# PA layout:
#   0x82F00000  trampoline code (36 bytes)
#   0x82F01000  source data (4KB, known pattern)
#   0x82F02000  dest data (4KB, zeroed then written)
#
# VA mapping (PA - 0x100200000 mod 2^64):
#   PA 0x82F00000 -> VA 0xFFFFFFFF82D00000
#   PA 0x82F01000 -> VA 0xFFFFFFFF82D01000
#   PA 0x82F02000 -> VA 0xFFFFFFFF82D02000

set pagination off
set confirm off

target remote 172.19.128.1:2331
file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

printf "=== High-Throughput Store Test ===\n"
printf "PC at connect: 0x%lx\n", $pc

# --- Configuration ---
set $memcpy_va    = 0xffffffff8041e1d0
set $ebreak_pa    = 0x82F00000
set $ebreak_va    = 0xFFFFFFFF82D00000
set $src_pa       = 0x82F01000
set $src_va       = 0xFFFFFFFF82D01000
set $dst_pa       = 0x82F02000
set $dst_va       = 0xFFFFFFFF82D02000
set $tramp_pa     = 0x82F00000
set $tramp_va     = 0xFFFFFFFF82D00000
set $test_size    = 2048

# --- Save original CPU state ---
set $save_pc  = $pc
set $save_sp  = $sp
set $save_ra  = $ra
set $save_a0  = $a0
set $save_a1  = $a1
set $save_a2  = $a2
set $save_s0  = $s0
set $save_s1  = $s1
set $save_s2  = $s2
set $save_s3  = $s3
set $save_s4  = $s4
set $save_s5  = $s5
printf "Saved CPU state (PC=0x%lx)\n", $save_pc

# --- Step 1: Write trampoline code via SBA ---
# Trampoline binary from /tmp/store_trampoline.bin (assembled)
# Contains: loop { bge s5,s4,done; mul t0,s5,s3; add a0,s1,t0; add a1,s2,t0;
#            mv a2,s3; jalr s0; addi s5,s5,1; j loop } done: ebreak
restore /tmp/store_trampoline.bin binary 0x82F00000
printf "Trampoline loaded at PA 0x82F00000 (36 bytes)\n"

# Also place a standalone ebreak after trampoline for Test A/B return
set *(unsigned int *)0x82F00100 = 0x00100073

# --- Step 2: Flush L2 for trampoline PAs ---
# L2 Flush64 MMIO at 0x2010200
set *(unsigned long long *)0x2010200 = 0x82F00000
set *(unsigned long long *)0x2010200 = 0x82F00040
set *(unsigned long long *)0x2010200 = 0x82F00100
printf "L2 flushed for trampoline\n"

# --- Step 3: Load source pattern via SBA ---
restore /tmp/store_test_pattern.bin binary 0x82F01000 0 2048
printf "Source pattern loaded at PA 0x82F01000 (2048 bytes)\n"

# --- Step 4: Zero destination via SBA ---
# Write 2KB of zeros
set $z = 0
while $z < 512
  set *(unsigned int *)($dst_pa + $z * 4) = 0
  set $z = $z + 1
end
printf "Destination zeroed at PA 0x82F02000 (2048 bytes)\n"

# ============================================
# TEST A: Single large aligned memcpy (ld/sd path)
# src and dst have same alignment mod 8 -> uses 128-byte ld/sd loop
# ============================================
printf "\n===== TEST A: Large aligned copy (2048B, ld/sd path) =====\n"

set $pc = $memcpy_va
set $a0 = $dst_va
set $a1 = $src_va
set $a2 = $test_size
set $ra = $ebreak_va + 0x100
# Stack needs to be valid for memcpy (it doesn't use stack, but just in case)

continue
printf "Test A done, PC=0x%lx\n", $pc

# Dump results
dump binary memory /tmp/store_test_A_dst.bin $dst_pa ($dst_pa + $test_size)
dump binary memory /tmp/store_test_A_src.bin $src_pa ($src_pa + $test_size)
printf "Test A results dumped to /tmp/store_test_A_{src,dst}.bin\n"

# ============================================
# TEST B: Large UNALIGNED memcpy (byte loop path)
# src%8 != dst%8 -> forces byte-by-byte copy
# src_va+1 (mod 8 = 1), dst_va (mod 8 = 0) -> different alignment
# ============================================
printf "\n===== TEST B: Large unaligned copy (2047B, byte path) =====\n"

# Re-zero destination
set $z = 0
while $z < 512
  set *(unsigned int *)($dst_pa + $z * 4) = 0
  set $z = $z + 1
end

set $pc = $memcpy_va
set $a0 = $dst_va
set $a1 = $src_va + 1
set $a2 = $test_size - 1
set $ra = $ebreak_va + 0x100

continue
printf "Test B done, PC=0x%lx\n", $pc

dump binary memory /tmp/store_test_B_dst.bin $dst_pa ($dst_pa + $test_size - 1)
printf "Test B results dumped to /tmp/store_test_B_dst.bin\n"
# Source for comparison: pattern starting from offset 1
dump binary memory /tmp/store_test_B_src.bin ($src_pa + 1) ($src_pa + $test_size)
printf "Test B source dumped to /tmp/store_test_B_src.bin\n"

# ============================================
# TEST C: Many small copies via trampoline (simulates printk)
# 64 copies of 32 bytes each -> 2048 bytes total
# Uses trampoline loop to minimize GDB stop overhead
# ============================================
printf "\n===== TEST C: 64x32B small copies (trampoline loop) =====\n"

# Re-zero destination
set $z = 0
while $z < 512
  set *(unsigned int *)($dst_pa + $z * 4) = 0
  set $z = $z + 1
end

# Set up trampoline registers
set $pc = $tramp_va
set $s0 = $memcpy_va
set $s1 = $dst_va
set $s2 = $src_va
set $s3 = 32
set $s4 = 64
set $s5 = 0
# sp must be valid (memcpy might not need it but jalr pushes ra)
# Actually memcpy doesn't touch stack, and our trampoline uses jalr which only sets ra

continue
printf "Test C done, PC=0x%lx\n", $pc

dump binary memory /tmp/store_test_C_dst.bin $dst_pa ($dst_pa + $test_size)
printf "Test C results dumped to /tmp/store_test_C_dst.bin\n"

# ============================================
# TEST D: Many small UNALIGNED copies (most likely to reproduce bug)
# 128 copies of 17 bytes each, src offset by 3 bytes
# 17 is prime, 3 offset ensures byte loop, and 17*128=2176 > 2048
# Use 120 copies of 17 bytes = 2040 bytes to stay within buffer
# ============================================
printf "\n===== TEST D: 120x17B unaligned copies (trampoline) =====\n"

# Re-zero destination
set $z = 0
while $z < 512
  set *(unsigned int *)($dst_pa + $z * 4) = 0
  set $z = $z + 1
end

# Flush L2 for trampoline again (in case it was evicted)
set *(unsigned long long *)0x2010200 = 0x82F00000
set *(unsigned long long *)0x2010200 = 0x82F00040

set $pc = $tramp_va
set $s0 = $memcpy_va
set $s1 = $dst_va
set $s2 = $src_va + 3
set $s3 = 17
set $s4 = 120
set $s5 = 0

continue
printf "Test D done, PC=0x%lx\n", $pc

dump binary memory /tmp/store_test_D_dst.bin $dst_pa ($dst_pa + 2040)
printf "Test D results dumped to /tmp/store_test_D_dst.bin\n"
# Source for comparison
dump binary memory /tmp/store_test_D_src.bin ($src_pa + 3) ($src_pa + 3 + 2040)

# ============================================
# Restore CPU state
# ============================================
printf "\n--- Restoring CPU state ---\n"
set $pc  = $save_pc
set $sp  = $save_sp
set $ra  = $save_ra
set $a0  = $save_a0
set $a1  = $save_a1
set $a2  = $save_a2
set $s0  = $save_s0
set $s1  = $save_s1
set $s2  = $save_s2
set $s3  = $save_s3
set $s4  = $save_s4
set $s5  = $save_s5
printf "CPU state restored to PC=0x%lx\n", $save_pc

printf "\n=== All tests complete ===\n"
printf "Verify with:\n"
printf "  cmp /tmp/store_test_A_src.bin /tmp/store_test_A_dst.bin\n"
printf "  cmp /tmp/store_test_B_src.bin /tmp/store_test_B_dst.bin\n"
printf "  cmp /tmp/store_test_A_src.bin /tmp/store_test_C_dst.bin\n"
printf "  python3 /tmp/store_test_verify.py\n"

detach
quit
