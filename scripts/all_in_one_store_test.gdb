# all_in_one_store_test.gdb
# Single script: walk page table, find writable VA, run memcpy via stepi, verify
set pagination off
set confirm off

target remote 172.19.128.1:2331
file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

printf "=== ALL-IN-ONE STORE TEST ===\n"
printf "PC=0x%lx SP=0x%lx\n", $pc, $sp

# Step 1: Read L2 page table (root=0x81FFF000, L2=0xFFFFE000)
# Dump first 30 entries to find mapped ranges
printf "\n--- L2 Page Table Scan ---\n"
set $l2 = 0xFFFFE000
set $i = 0
while $i < 30
  set $pte = *(unsigned long long *)($l2 + $i * 8)
  if ($pte & 1) != 0
    set $ppn = ($pte >> 10) & 0xFFFFFFFFFFF
    set $r = ($pte >> 1) & 1
    set $w = ($pte >> 2) & 1
    set $x = ($pte >> 3) & 1
    printf "  L2[%2d] V=1 R=%d W=%d X=%d PPN=0x%lx (PA=0x%lx) → VA 0xffffffff%lx\n", $i, $r, $w, $x, $ppn, $ppn*4096, 0x80000000 + (unsigned long long)$i * 0x200000
  end
  set $i = $i + 1
end

# Step 2: Use SP-area for test (guaranteed R+W)  
# SP=0xffffffff80e02de0 → stack is in L2[VPN1=6] (VA 0xffffffff80C00000-0xffffffff80DFFFFF)
# Wait, 0x80e02de0: let me compute VPN[1]
# Easier: use SP page directly. Write test data to SP-512 (well within current page)
set $save_pc = $pc
set $save_ra = $ra
set $save_a0 = $a0
set $save_a1 = $a1
set $save_a2 = $a2
set $save_t6 = $t6

# Use a small offset from SP as dest (same page, guaranteed mapped R+W)
set $dst_va = ($sp - 512) & ~0x7
set $dst_pa = $dst_va + 0x100200000

# Use kernel .rodata for source (read-only but readable)
# Actually, use a VA in .data section that we know is mapped
# Let's use .text (read-safe) for source and SP-area for dest
set $src_va = 0xffffffff80200000
set $src_pa = 0x80200000

printf "\n--- Test Setup ---\n"
printf "dst_va=0x%lx dst_pa=0x%lx\n", $dst_va, $dst_pa
printf "src_va=0x%lx src_pa=0x%lx\n", $src_va, $src_pa

# Step 3: Run aligned memcpy(dst, src, 128) via stepi
# This copies 128 bytes from kernel .text to stack area
printf "\n--- TEST 1: memcpy 128B aligned (ld/sd path) ---\n"

set $pc = 0xffffffff8041e1d0
set $a0 = $dst_va
set $a1 = $src_va
set $a2 = 128
set $ra = $save_pc
stepi 60
printf "After stepi 60: PC=0x%lx (expect 0x%lx)\n", $pc, $save_pc

# Compare: read 128 bytes from dst_pa via SBA and src_pa via SBA
printf "Comparing first 32 bytes:\n"
set $errs = 0
set $ci = 0
while $ci < 32
  set $s = *(unsigned char *)($src_pa + $ci)
  set $d = *(unsigned char *)($dst_pa + $ci)
  if $s != $d
    printf "  MISMATCH @%d: src=0x%02x dst=0x%02x\n", $ci, $s, $d
    set $errs = $errs + 1
  end
  set $ci = $ci + 1
end
if $errs == 0
  printf "  First 32 bytes: MATCH\n"
end

# Dump for host-side verification
dump binary memory /tmp/st1_src.bin $src_pa ($src_pa + 128)
dump binary memory /tmp/st1_dst.bin $dst_pa ($dst_pa + 128)

# Step 4: Test unaligned memcpy (byte loop) - 32 bytes
printf "\n--- TEST 2: memcpy 32B unaligned (byte loop) ---\n"

# Zero the dest area first
set $zi = 0
while $zi < 8
  set *(unsigned long long *)($dst_pa + $zi * 8) = 0
  set $zi = $zi + 1
end

set $pc = 0xffffffff8041e1d0
set $a0 = $dst_va
set $a1 = $src_va + 1
set $a2 = 32
set $ra = $save_pc
# Unaligned: 32 < 128, goes to tail. src+1 not 4-aligned → byte loop
# 4 insns × 32 bytes + setup ~6 = ~134
stepi 140
printf "After stepi 140: PC=0x%lx (expect 0x%lx)\n", $pc, $save_pc

printf "Comparing 32 bytes:\n"
set $errs = 0
set $ci = 0
while $ci < 32
  set $s = *(unsigned char *)($src_pa + 1 + $ci)
  set $d = *(unsigned char *)($dst_pa + $ci)
  if $s != $d
    printf "  MISMATCH @%d: src=0x%02x dst=0x%02x\n", $ci, $s, $d
    set $errs = $errs + 1
  end
  set $ci = $ci + 1
end
if $errs == 0
  printf "  32 bytes: MATCH\n"
end

dump binary memory /tmp/st2_src.bin ($src_pa + 1) ($src_pa + 33)
dump binary memory /tmp/st2_dst.bin $dst_pa ($dst_pa + 32)

# Restore
set $pc = $save_pc
set $ra = $save_ra
set $a0 = $save_a0
set $a1 = $save_a1
set $a2 = $save_a2
set $t6 = $save_t6

printf "\n=== Tests complete ===\n"
printf "cmp /tmp/st1_src.bin /tmp/st1_dst.bin\n"
printf "cmp /tmp/st2_src.bin /tmp/st2_dst.bin\n"

detach
quit
