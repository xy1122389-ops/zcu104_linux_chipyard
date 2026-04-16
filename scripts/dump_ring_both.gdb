# dump_ring_both.gdb — dump BOTH printk_info descriptors AND data ring
# for offline analysis of 2-byte duplication root cause
set confirm off
set pagination off

target remote 172.19.128.1:2331
file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

printf "Connected. PC=0x%lx\n", $pc

# ---- Read key addresses via SBA ----
# log_buf pointer (VA stored at PA 0x80ebf368)
set $log_buf_ptr_pa = 0x80ebf368
set $log_buf_va = *(unsigned long long *)$log_buf_ptr_pa
printf "log_buf VA = 0x%lx\n", $log_buf_va

# log_buf_len (at PA 0x80ebf370)  
set $log_buf_len_pa = 0x80ebf370
set $log_buf_len = *(unsigned int *)$log_buf_len_pa
printf "log_buf_len = %d (0x%x)\n", $log_buf_len, $log_buf_len

# Convert log_buf VA to PA
# For lowmem (0xffffffd8...): PA = VA - 0xffffffd800000000 + 0x80000000
# For kernel  (0xffffffff8...): PA = VA + 0x100200000 (mod 2^64)
# Check which range
set $log_buf_pa = $log_buf_va + 0x100200000
printf "log_buf PA = 0x%lx (assuming kernel range)\n", $log_buf_pa

# If relocated to lowmem range, try alternative
# We'll detect by checking if PA is in DDR range 0x80000000-0xFFFFFFFF
# Just dump using known good PA computation

# __log_buf (static, always at known PA)
set $static_log_buf_pa = 0x80ed0060
printf "__log_buf PA = 0x%lx\n", $static_log_buf_pa

# _printk_rb_static_infos (descriptor array)
set $infos_pa = 0x80E15EF0
printf "printk_info array PA = 0x%lx\n", $infos_pa

# --- Dump data ring ---
# Use actual log_buf PA
printf "Dumping data ring (%d bytes)...\n", $log_buf_len
set $data_end = $log_buf_pa + $log_buf_len
dump binary memory /tmp/ring_data.bin $log_buf_pa $data_end
printf "  -> /tmp/ring_data.bin\n"

# Also dump the static __log_buf for comparison
set $static_end = $static_log_buf_pa + 131072
dump binary memory /tmp/ring_data_static.bin $static_log_buf_pa $static_end
printf "  -> /tmp/ring_data_static.bin (static 128KB)\n"

# --- Dump printk_info descriptor array ---
# sizeof(printk_info) = 88 bytes (with padding)
# Default max entries = LOG_BUF_LEN / 8 = 16384 for 128KB
# But for safety, let's dump 2048 entries = 2048 * 88 = 180224 bytes
set $info_count = 2048
set $info_size = 88
set $info_total = $info_count * $info_size
set $info_end = $infos_pa + $info_total
dump binary memory /tmp/ring_infos.bin $infos_pa $info_end
printf "  -> /tmp/ring_infos.bin (%d entries, %d bytes)\n", $info_count, $info_total

# --- Also read prb (printk_ringbuffer) state ---
# prb is at VA printk_rb_static → need its PA
# Key fields: desc_ring.count_bits, text_data_ring.size_bits
# For now, let's just read the desc committed count
# desc_ring is embedded in prb

printf "\nDone. Run: python3 /tmp/analyze_ring.py\n"
detach
quit
