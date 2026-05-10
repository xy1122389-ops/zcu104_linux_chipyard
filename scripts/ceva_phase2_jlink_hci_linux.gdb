# Phase 2 GDB script: CEVA BT5.2 Linux kernel module boot verification
# Verify that after payload load, ceva_bt52.ko is loaded from initramfs
# and hci0 device is registered successfully.
#
# Test objective: Phase 2 "insmod hci0" milestone verification
# Prerequisites:
#   - Phase 1A bitstream flashed (EM MMIO RTL active)
#   - Payload built with BT modules in initramfs
#   - J-Link 127.0.0.1:3333

set confirm off
set remotetimeout 30
set pagination off

define p32
  printf "0x%08X\n", *(unsigned int*)$arg0
end

set $JLINK_HOST = "127.0.0.1"
set $JLINK_PORT = 3333

target remote 127.0.0.1:3333
monitor halt

printf "=== Phase 2: CEVA BT5.2 Linux Module Boot Verification ===\n"
printf "Phase 2 Goal: hci0 registered in dmesg after insmod\n"

# Check current state
printf "\n--- Initial State ---\n"
printf "PC: 0x%016llX\n", $pc
printf "a0: 0x%016llX\n", $a0

# Let kernel boot with BT module loading
printf "\n--- Running kernel for 60s (module load happens at init) ---\n"
monitor go

# Wait for kernel to boot and init script to run insmod
shell sleep 60

monitor halt
printf "PC after 60s: 0x%016llX\n", $pc

# Inspect kernel log for BT module loading evidence
# The init script logs:
#   "ceva-bt52: bluetooth.ko OK"
#   "ceva-bt52: ceva_bt52.ko OK"
#   "ceva-bt52: hci0 registered OK"
#
# We verify via physical magic write: 
# Init script will write to /dev/mem if hci0 is registered
# For now, verify via klog scan

# VA->PA: 0xffffffff80xxxxxx → 0x80200000 + (VA - 0xffffffff80000000)
# log_buf symbol check
printf "\n--- Checking kernel log_buf ---\n"
set $log_buf_va = (unsigned long long)log_buf
printf "log_buf VA: 0x%016llX\n", $log_buf_va
set $log_len = (unsigned int)log_buf_len
printf "log_buf_len: %u\n", $log_len

# PA = VA + 0x100200000 (mod 2^64) for RV kernel at 0x80200000
set $log_buf_pa = ($log_buf_va + 0x100200000ULL) & 0xFFFFFFFFULL
printf "log_buf PA: 0x%08X\n", $log_buf_pa

# Dump first 2KB of log for ceva-bt52 strings
printf "\n--- klog dump (raw, first 2048 bytes from PA) ---\n"
dump binary memory /tmp/phase2_klog.bin $log_buf_pa ($log_buf_pa + 2048)

# Check key CEVA BT milestone strings in log
shell grep -c "ceva-bt52\|hci0\|bluetooth" /tmp/phase2_klog.bin 2>/dev/null && echo "STRINGS_FOUND" || echo "STRINGS_NOT_FOUND"

# Direct read of first 64 bytes to detect any ceva-bt52 log
printf "\n--- DM registers verification ---\n"
set $CEVA_BASE = 0x65000000
printf "DM_VERSION:  0x%08X\n", *(unsigned int*)($CEVA_BASE + 0x0004)
printf "DM_INTSTAT0: 0x%08X\n", *(unsigned int*)($CEVA_BASE + 0x000C)
printf "DM_INTSTAT1: 0x%08X\n", *(unsigned int*)($CEVA_BASE + 0x001C)
printf "DM_RWDMCNTL: 0x%08X\n", *(unsigned int*)($CEVA_BASE + 0x0000)

# Check EM MMIO window (Phase 1A)
set $EM_BASE = 0x65010000
printf "\n--- EM MMIO window check ---\n"
printf "EM[0]: 0x%08X (ETPTR area)\n", *(unsigned int*)$EM_BASE
printf "EM[1]: 0x%08X\n", *(unsigned int*)($EM_BASE + 4)
printf "EM[64]: 0x%08X (cmd buf)\n", *(unsigned int*)($EM_BASE + 256)

# Phase 2 PASS criteria:
# 1. DM_VERSION != 0xFFFFFFFF (CEVA accessible)
# 2. EM[0] accessible (EM MMIO working)
# 3. ceva_bt52 strings in klog
set $dm_ver = *(unsigned int*)($CEVA_BASE + 0x0004)
set $em_word0 = *(unsigned int*)$EM_BASE

printf "\n=== Phase 2 Verification Summary ===\n"

if $dm_ver != 0xFFFFFFFF
  printf "CHECK 1: DM_VERSION=0x%08X - PASS (CEVA accessible)\n", $dm_ver
else
  printf "CHECK 1: DM_VERSION=0xFFFFFFFF - FAIL (no response)\n"
end

if $em_word0 != 0xFFFFFFFF
  printf "CHECK 2: EM[0]=0x%08X - PASS (EM MMIO accessible)\n", $em_word0
else
  printf "CHECK 2: EM MMIO FAIL (0xFFFFFFFF)\n"
end

# BT_RWBTCNTL should show BT enabled (bit 8)
set $bt_cntl = *(unsigned int*)($CEVA_BASE + 0x0800)
printf "CHECK 3: BT_RWBTCNTL=0x%08X (bit8=RWBTEN should be set by driver open)\n", $bt_cntl

# Check PLIC state
set $PLIC_BASE = 0x0C000000
printf "\n--- PLIC state (after module load) ---\n"
printf "PLIC IRQ1 priority: 0x%08X\n", *(unsigned int*)($PLIC_BASE + 0x4)
printf "PLIC pending[31:0]: 0x%08X\n", *(unsigned int*)($PLIC_BASE + 0x1000)
printf "PLIC S-mode enable: 0x%08X\n", *(unsigned int*)($PLIC_BASE + 0x2080)
printf "PLIC S-mode thresh: 0x%08X\n", *(unsigned int*)($PLIC_BASE + 0x201000)

printf "\n=== Phase 2 DONE ===\n"
printf "Check /tmp/phase2_klog.bin for 'ceva-bt52' strings\n"
printf "If hci0 visible: Phase 2 PASS\n"

monitor go
detach
quit
