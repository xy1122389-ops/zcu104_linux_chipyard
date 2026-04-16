# dump_ring_both2.gdb — dump printk_info + data ring with correct PAs
set confirm off
set pagination off

target remote 172.19.128.1:2331
file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

printf "Connected. PC=0x%lx\n", $pc

# Correct PAs (from nm + VA→PA conversion)
set $log_buf_pa     = 0x810caf30
set $log_buf_len_pa = 0x810caf28
set $static_log_buf_pa = 0x810dc190
set $infos_pa       = 0x810170c0

# Read log_buf pointer and len
set $log_buf_va = *(unsigned long long *)$log_buf_pa
set $log_buf_len_val = *(unsigned int *)$log_buf_len_pa
printf "log_buf VA = 0x%lx\n", $log_buf_va
printf "log_buf_len = %d (0x%x)\n", $log_buf_len_val, $log_buf_len_val

# Convert log_buf VA to PA
# log_buf might have been reallocated to a different VA range
# If still __log_buf: VA=0xffffffff80edc190 → PA=0x810dc190
# If relocated to lowmem: VA=0xffffffd8XXXXXXXX → PA = VA - 0xffffffd800000000 + 0x80000000
# Check:
set $actual_data_pa = $static_log_buf_pa

# If log_buf_va != __log_buf VA, it was relocated
if $log_buf_va != 0xffffffff80edc190
  printf "log_buf was RELOCATED from __log_buf!\n"
  printf "Checking if lowmem range...\n"
  # Can't do conditional PA calc in GDB easily, use static for now
end

printf "Using data PA = 0x%lx\n", $actual_data_pa

# Determine dump size  
set $dump_size = $log_buf_len_val
if $dump_size == 0
  set $dump_size = 131072
  printf "log_buf_len=0, using default 128KB\n"
end

# Dump data ring
set $data_end = $actual_data_pa + $dump_size
printf "Dumping data ring: PA 0x%lx - 0x%lx (%d bytes)\n", $actual_data_pa, $data_end, $dump_size
dump binary memory /tmp/ring_data.bin $actual_data_pa $data_end

# Dump printk_info descriptors
# sizeof(printk_info) = 88 with alignment
# Dump enough for 2048 entries = 180224 bytes
set $info_count = 2048
set $info_bytes = $info_count * 88
set $info_end = $infos_pa + $info_bytes
printf "Dumping infos: PA 0x%lx - 0x%lx (%d entries)\n", $infos_pa, $info_end, $info_count
dump binary memory /tmp/ring_infos.bin $infos_pa $info_end

# Also dump printk_rb_static structure to understand ring config
set $prb_pa = 0x81017050
dump binary memory /tmp/ring_prb.bin $prb_pa ($prb_pa + 256)

printf "\nDumps complete.\n"
printf "  /tmp/ring_data.bin  — data ring (%d bytes)\n", $dump_size
printf "  /tmp/ring_infos.bin — printk_info array\n"
printf "  /tmp/ring_prb.bin   — prb structure\n"
printf "\nRun: python3 /tmp/analyze_ring.py\n"

detach
quit
