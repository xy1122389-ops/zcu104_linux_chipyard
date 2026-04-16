# high_throughput_store_test_v2.gdb
# Tests if memcpy through Sv39 MMU causes data corruption
# Uses hbreak (hardware breakpoint) for stopping — no executable memory needed
# After each memcpy, flushes L2 to force DDR writeback, then SBA-reads to verify
#
# PA layout:
#   0x82F01000  source data (2KB, known pattern from file)
#   0x82F02000  dest data (2KB, zeroed then written)
#
# VA mapping (VA = PA - 0x100200000 mod 2^64):
#   PA 0x82F01000 -> VA 0xFFFFFFFF82D01000
#   PA 0x82F02000 -> VA 0xFFFFFFFF82D02000

set pagination off
set confirm off

target remote 172.19.128.1:2331
file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

printf "=== High-Throughput Store Test v2 ===\n"
printf "PC at connect: 0x%lx\n", $pc

# --- Configuration ---
set $memcpy_va    = 0xffffffff8041e1d0
set $src_pa       = 0x82F01000
set $src_va       = 0xFFFFFFFF82D01000
set $dst_pa       = 0x82F02000
set $dst_va       = 0xFFFFFFFF82D02000
set $test_size    = 2048

# Use strlen as return target (in .text, executable, not called by memcpy)
set $return_va    = 0xffffffff80496470

# L2 Flush64 MMIO
set $l2_flush     = 0x2010200

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

# --- Load source pattern via SBA ---
restore /tmp/store_test_pattern.bin binary 0x82F01000 0 2048
printf "Source pattern loaded at PA 0x82F01000 (2048 bytes)\n"

# Flush L2 for source (so CPU reads from DDR, not stale L2)
set $fl = 0
while $fl < 2048
  set *(unsigned long long *)$l2_flush = $src_pa + $fl
  set $fl = $fl + 64
end
printf "L2 flushed for source\n"

# === Helper: zero destination ===
define zero_dst
  set $z = 0
  while $z < 512
    set *(unsigned int *)($dst_pa + $z * 4) = 0
    set $z = $z + 1
  end
  # Flush L2 for dest
  set $fl = 0
  while $fl < 2048
    set *(unsigned long long *)$l2_flush = $dst_pa + $fl
    set $fl = $fl + 64
  end
end

# === Helper: flush L2 for dest region ===
define flush_dst
  set $fl = 0
  while $fl < 2048
    set *(unsigned long long *)$l2_flush = $dst_pa + $fl
    set $fl = $fl + 64
  end
end

# === Helper: call memcpy(dst, src, len) and wait ===
# Uses hbreak at return address
define call_memcpy
  # Args already set: $a0=dst, $a1=src, $a2=len
  set $pc = $memcpy_va
  set $ra = $return_va
  hbreak *$return_va
  continue
  delete breakpoints
end

# ============================================
# TEST A: Single large aligned memcpy (ld/sd path)
# src and dst same alignment mod 8 -> uses 128-byte ld/sd loop
# ============================================
printf "\n===== TEST A: Aligned 2048B copy (ld/sd path) =====\n"
zero_dst

set $a0 = $dst_va
set $a1 = $src_va
set $a2 = $test_size
call_memcpy
printf "memcpy returned, PC=0x%lx\n", $pc

# Flush L2 to force DDR writeback, then SBA-dump
flush_dst
dump binary memory /tmp/store_test_A_dst.bin $dst_pa ($dst_pa + $test_size)
dump binary memory /tmp/store_test_A_src.bin $src_pa ($src_pa + $test_size)
printf "Test A dumped.\n"

# Quick inline verify (first 32 bytes)
set $err_a = 0
set $qi = 0
while $qi < 32
  set $exp = *(unsigned char *)($src_pa + $qi)
  set $got = *(unsigned char *)($dst_pa + $qi)
  if $exp != $got
    printf "  A ERR @%d: exp=0x%02x got=0x%02x\n", $qi, $exp, $got
    set $err_a = $err_a + 1
  end
  set $qi = $qi + 1
end
if $err_a == 0
  printf "  A: first 32 bytes OK\n"
end

# ============================================
# TEST B: Large UNALIGNED memcpy (byte loop path)
# src offset +1, different mod-8 alignment -> byte loop
# ============================================
printf "\n===== TEST B: Unaligned 2047B copy (byte path) =====\n"
zero_dst

set $a0 = $dst_va
set $a1 = $src_va + 1
set $a2 = $test_size - 1
call_memcpy
printf "memcpy returned, PC=0x%lx\n", $pc

flush_dst
dump binary memory /tmp/store_test_B_dst.bin $dst_pa ($dst_pa + $test_size - 1)
dump binary memory /tmp/store_test_B_src.bin ($src_pa + 1) ($src_pa + $test_size)
printf "Test B dumped.\n"

# Quick inline verify
set $err_b = 0
set $qi = 0
while $qi < 32
  set $exp = *(unsigned char *)($src_pa + 1 + $qi)
  set $got = *(unsigned char *)($dst_pa + $qi)
  if $exp != $got
    printf "  B ERR @%d: exp=0x%02x got=0x%02x\n", $qi, $exp, $got
    set $err_b = $err_b + 1
  end
  set $qi = $qi + 1
end
if $err_b == 0
  printf "  B: first 32 bytes OK\n"
end

# ============================================
# TEST C: Many small unaligned copies (GDB loop)
# 40 copies of varying sizes (17-39 bytes)
# dst offset accumulates -> hits different PA%8 positions
# ============================================
printf "\n===== TEST C: 40 small unaligned copies (17-39B each) =====\n"
zero_dst

set $offset = 0
set $mi = 0
set $err_c_total = 0
while $mi < 40
  # Message length varies: 17 + (mi % 7) * 3 = 17,20,23,26,29,32,35
  set $mlen = 17 + ($mi % 7) * 3
  
  # Use unaligned src: src_va + 3 + offset (mod 8 = 3 initially)
  set $a0 = $dst_va + $offset
  set $a1 = $src_va + 3 + $offset
  set $a2 = $mlen
  call_memcpy
  
  set $offset = $offset + $mlen
  set $mi = $mi + 1
end
printf "40 copies done, total %d bytes written\n", $offset

# Flush and dump
flush_dst
dump binary memory /tmp/store_test_C_dst.bin $dst_pa ($dst_pa + $offset)
dump binary memory /tmp/store_test_C_src.bin ($src_pa + 3) ($src_pa + 3 + $offset)
printf "Test C dumped (%d bytes)\n", $offset

# Quick inline verify first 64 bytes
set $err_c = 0
set $qi = 0
while $qi < 64
  set $exp = *(unsigned char *)($src_pa + 3 + $qi)
  set $got = *(unsigned char *)($dst_pa + $qi)
  if $exp != $got
    printf "  C ERR @%d: exp=0x%02x got=0x%02x\n", $qi, $exp, $got
    set $err_c = $err_c + 1
  end
  set $qi = $qi + 1
end
if $err_c == 0
  printf "  C: first 64 bytes OK\n"
end

# ============================================
# TEST D: Many copies with L2 eviction between each
# 20 copies of 32 bytes, with L2 flush after each write
# This forces DDR roundtrip for each copy
# ============================================
printf "\n===== TEST D: 20x32B copies with L2 flush each =====\n"
zero_dst

set $offset = 0
set $mi = 0
while $mi < 20
  set $mlen = 32
  
  set $a0 = $dst_va + $offset
  set $a1 = $src_va + 5 + $offset
  set $a2 = $mlen
  call_memcpy
  
  # Flush L2 for this chunk immediately (force DDR writeback)
  set $faddr = $dst_pa + $offset
  set *(unsigned long long *)$l2_flush = $faddr
  if $faddr + 32 > (($faddr >> 6) << 6) + 64
    # Crosses cache line boundary, flush next line too
    set *(unsigned long long *)$l2_flush = $faddr + 32
  end
  
  set $offset = $offset + $mlen
  set $mi = $mi + 1
end
printf "20 copies done, total %d bytes\n", $offset

flush_dst
dump binary memory /tmp/store_test_D_dst.bin $dst_pa ($dst_pa + $offset)
dump binary memory /tmp/store_test_D_src.bin ($src_pa + 5) ($src_pa + 5 + $offset)
printf "Test D dumped (%d bytes)\n", $offset

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
printf "Full verify: python3 /tmp/store_test_verify.py\n"

detach
quit
