# high_throughput_store_test_v3.gdb
# Simplified store test: uses hbreak, restore for fast I/O, inline code
#
# Tests if memcpy through Sv39 MMU causes data corruption
# After each memcpy, flushes L2 (force DDR writeback), then SBA-dump for host verify

set pagination off
set confirm off

target remote 172.19.128.1:2331
file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

printf "=== Store Test v3 ===\n"
printf "PC=0x%lx\n", $pc

set $memcpy_va = 0xffffffff8041e1d0
set $src_pa    = 0x82F01000
set $src_va    = 0xFFFFFFFF82D01000
set $dst_pa    = 0x82F02000
set $dst_va    = 0xFFFFFFFF82D02000
set $ret_va    = 0xffffffff80496470
set $l2_flush  = 0x2010200
set $sz        = 2048

# Save state
set $S_pc  = $pc
set $S_sp  = $sp
set $S_ra  = $ra
set $S_a0  = $a0
set $S_a1  = $a1
set $S_a2  = $a2

# Note: sstatus CSR not directly accessible via J-Link, skip interrupt disable
printf "Proceeding without interrupt disable\n"

# Load source via SBA
restore /tmp/store_test_pattern.bin binary 0x82F01000 0 2048
printf "Source loaded\n"

# Flush L2 for source
set $f = 0
while $f < $sz
  set *(unsigned long long *)$l2_flush = $src_pa + $f
  set $f = $f + 64
end

# ===== TEST A: Aligned 2048B (ld/sd path) =====
printf "\n--- TEST A: aligned 2048B ---\n"
# Zero dest via SBA
restore /tmp/zeros_2k.bin binary 0x82F02000 0 2048

set $pc = $memcpy_va
set $a0 = $dst_va
set $a1 = $src_va
set $a2 = $sz
set $ra = $ret_va
hbreak *$ret_va
continue
delete breakpoints
printf "A: PC=0x%lx (expect 0x%lx)\n", $pc, $ret_va

# Flush L2 for dest -> DDR
set $f = 0
while $f < $sz
  set *(unsigned long long *)$l2_flush = $dst_pa + $f
  set $f = $f + 64
end

# Dump
dump binary memory /tmp/st_A_dst.bin $dst_pa ($dst_pa + $sz)
dump binary memory /tmp/st_A_src.bin $src_pa ($src_pa + $sz)
printf "A: dumped\n"

# ===== TEST B: Unaligned 2047B (byte loop) =====
printf "\n--- TEST B: unaligned 2047B ---\n"
restore /tmp/zeros_2k.bin binary 0x82F02000 0 2048

set $pc = $memcpy_va
set $a0 = $dst_va
set $a1 = $src_va + 1
set $a2 = $sz - 1
set $ra = $ret_va
hbreak *$ret_va
continue
delete breakpoints
printf "B: PC=0x%lx\n", $pc

set $f = 0
while $f < $sz
  set *(unsigned long long *)$l2_flush = $dst_pa + $f
  set $f = $f + 64
end
dump binary memory /tmp/st_B_dst.bin $dst_pa ($dst_pa + $sz - 1)
dump binary memory /tmp/st_B_src.bin ($src_pa + 1) ($src_pa + $sz)
printf "B: dumped\n"

# ===== TEST C: 20 small unaligned copies =====
printf "\n--- TEST C: 20 small copies ---\n"
restore /tmp/zeros_2k.bin binary 0x82F02000 0 2048

set $off = 0
set $i = 0
while $i < 20
  set $mlen = 17 + ($i % 7) * 3
  set $pc = $memcpy_va
  set $a0 = $dst_va + $off
  set $a1 = $src_va + 3 + $off
  set $a2 = $mlen
  set $ra = $ret_va
  hbreak *$ret_va
  continue
  delete breakpoints
  set $off = $off + $mlen
  set $i = $i + 1
end
printf "C: %d copies, %d bytes total, PC=0x%lx\n", $i, $off

set $f = 0
while $f < $sz
  set *(unsigned long long *)$l2_flush = $dst_pa + $f
  set $f = $f + 64
end
dump binary memory /tmp/st_C_dst.bin $dst_pa ($dst_pa + $off)
dump binary memory /tmp/st_C_src.bin ($src_pa + 3) ($src_pa + 3 + $off)
printf "C: dumped\n"

# ===== Restore =====
set $pc = $S_pc
set $sp = $S_sp
set $ra = $S_ra
set $a0 = $S_a0
set $a1 = $S_a1
set $a2 = $S_a2
printf "\nState restored. PC=0x%lx\n", $S_pc
printf "Verify: python3 /tmp/store_test_verify_v3.py\n"

detach
quit
