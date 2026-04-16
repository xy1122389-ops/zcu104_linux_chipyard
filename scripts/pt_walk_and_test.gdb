# pt_walk_and_test.gdb
# Walk page table for test VA, then run memcpy if mapped

set pagination off
set confirm off

target remote 172.19.128.1:2331
file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

printf "PC=0x%lx SP=0x%lx\n", $pc, $sp

# Read satp
monitor ReadCSR 0x180

# Known: satp PPN = 0x81FFF, root PT at PA 0x81FFF000
# VPN[2] = 510 for all VA 0xFFFFFFFF80000000-0xFFFFFFFFBFFFFFFF
# Read L1 PTE for VPN[2]=510
set $l1_pte = *(unsigned long long *)0x81FFFFF0
printf "L1 PTE[510] = 0x%lx (V=%d R=%d W=%d X=%d)\n", $l1_pte, $l1_pte&1, ($l1_pte>>1)&1, ($l1_pte>>2)&1, ($l1_pte>>3)&1

# If RWX=0 and V=1, it's a pointer to L2 table
set $l2_base_pa = (($l1_pte >> 10) & 0xFFFFFFFFFFF) * 4096
printf "L2 table PA = 0x%lx\n", $l2_base_pa

# Check L2 PTE for kernel PC (VPN[1] = 2 for VA 0xFFFFFFFF804xxxxx)
set $l2_pte_pc = *(unsigned long long *)($l2_base_pa + 2 * 8)
printf "L2 PTE[2] (PC area) = 0x%lx (V=%d R=%d W=%d X=%d)\n", $l2_pte_pc, $l2_pte_pc&1, ($l2_pte_pc>>1)&1, ($l2_pte_pc>>2)&1, ($l2_pte_pc>>3)&1

# Check L2 PTE for stack (VPN[1] from SP)
set $sp_vpn1 = ($sp >> 21) & 0x1FF
set $l2_pte_sp = *(unsigned long long *)($l2_base_pa + $sp_vpn1 * 8)
printf "L2 PTE[%d] (SP area) = 0x%lx (V=%d R=%d W=%d X=%d)\n", $sp_vpn1, $l2_pte_sp, $l2_pte_sp&1, ($l2_pte_sp>>1)&1, ($l2_pte_sp>>2)&1, ($l2_pte_sp>>3)&1

# Check L2 PTE for test area (VPN[1] = 22 for VA 0xFFFFFFFF82Dxxxxx)
set $l2_pte_test = *(unsigned long long *)($l2_base_pa + 22 * 8)
printf "L2 PTE[22] (test area) = 0x%lx (V=%d R=%d W=%d X=%d)\n", $l2_pte_test, $l2_pte_test&1, ($l2_pte_test>>1)&1, ($l2_pte_test>>2)&1, ($l2_pte_test>>3)&1

# Check a few more L2 PTEs to find the map extent
printf "\nL2 PTE scan (VPN[1] 0-30):\n"
set $vi = 0
while $vi <= 30
  set $pte = *(unsigned long long *)($l2_base_pa + $vi * 8)
  if ($pte & 1) != 0
    printf "  L2[%2d] = 0x%lx (V=%d R=%d W=%d X=%d) → PA 0x%lx\n", $vi, $pte, $pte&1, ($pte>>1)&1, ($pte>>2)&1, ($pte>>3)&1, (($pte >> 10) & 0xFFFFFFFFFFF) * 4096
  end
  set $vi = $vi + 1
end

detach
quit
