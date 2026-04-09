set pagination off
set confirm off
set remotetimeout 60

target remote 172.19.128.1:12331
monitor halt

# Install block copy code at 0x81200000
# fence.i; ld a3,0(a0); sd a3,0(a2); addi a0,8; addi a2,8; blt a0,a1,-16; ebreak
set *(unsigned int*)0x81200000 = 0x0000100f
set *(unsigned int*)0x81200004 = 0x00053683
set *(unsigned int*)0x81200008 = 0x00d63023
set *(unsigned int*)0x8120000c = 0x00850513
set *(unsigned int*)0x81200010 = 0x00860613
set *(unsigned int*)0x81200014 = 0xFEB548E3
set *(unsigned int*)0x81200018 = 0x00100073

# Copy 16KB from __log_buf (PA 0x80ed0060) to buffer (PA 0x81300000)
set $a0 = 0x80ed0060
set $a1 = 0x80ed4060
set $a2 = 0x81300000
set $pc = 0x81200000
hbreak *0x81200018
continue
delete breakpoints

# SBA dump to file
dump binary memory /tmp/klog_boot6.bin 0x81300000 0x81304000
echo [ok] Dumped 16KB to /tmp/klog_boot6.bin\n
quit
