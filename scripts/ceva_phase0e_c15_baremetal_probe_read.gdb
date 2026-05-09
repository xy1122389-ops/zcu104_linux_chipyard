# Draft-only Phase 0E-C1.5 J-Link/GDB readback for the compiled baremetal IRQ skeleton.
#
# This script is intentionally read-mostly. It consumes the compiled sdboot.elf
# for symbol resolution and only reads live MMIO registers that do not have a
# destructive read side effect. PLIC claim/complete is therefore skipped.

set confirm off
set pagination off
set remotetimeout 15

echo \n=== Phase 0E-C1.5 baremetal probe read draft ===\n

monitor go
python
import time
time.sleep(40.0)
end
monitor halt

printf "LIVE_PC=0x%016llX\n", (unsigned long long)$pc
echo LIVE_MCAUSE_REG=UNAVAILABLE_GDB_INVALID_CAST\n

printf "PROBE_ADDR_MAGIC=0x%08X\n", (unsigned int)&phase0e_irq_probe_magic
printf "PROBE_ADDR_MCAUSE=0x%08X\n", (unsigned int)&phase0e_irq_probe_mcause
printf "PROBE_ADDR_MEPC=0x%08X\n", (unsigned int)&phase0e_irq_probe_mepc
printf "PROBE_ADDR_MTVAL=0x%08X\n", (unsigned int)&phase0e_irq_probe_mtval
printf "PROBE_ADDR_CLAIM_ID=0x%08X\n", (unsigned int)&phase0e_irq_probe_claim_id
printf "PROBE_ADDR_PLIC_PENDING_BEFORE_CLAIM=0x%08X\n", (unsigned int)&phase0e_irq_probe_plic_pending_before_claim
printf "PROBE_ADDR_PLIC_PENDING_AFTER_ACK=0x%08X\n", (unsigned int)&phase0e_irq_probe_plic_pending_after_ack
printf "PROBE_ADDR_CEVA_STATUS_BEFORE_ACK=0x%08X\n", (unsigned int)&phase0e_irq_probe_ceva_status_before_ack
printf "PROBE_ADDR_CEVA_STATUS_AFTER_ACK=0x%08X\n", (unsigned int)&phase0e_irq_probe_ceva_status_after_ack
printf "PROBE_ADDR_COMPLETION_WRITTEN=0x%08X\n", (unsigned int)&phase0e_irq_probe_completion_written
printf "PROBE_ADDR_HANDLER_COUNT=0x%08X\n", (unsigned int)&phase0e_irq_probe_handler_count
printf "PROBE_ADDR_TARGET_COUNT=0x%08X\n", (unsigned int)&phase0e_irq_probe_target_count
printf "PROBE_ADDR_DONE=0x%08X\n", (unsigned int)&phase0e_irq_probe_done
printf "PROBE_ADDR_TIMEOUT=0x%08X\n", (unsigned int)&phase0e_irq_probe_timeout

printf "PROBE_MAGIC=0x%08X\n", phase0e_irq_probe_magic
printf "PROBE_MCAUSE=0x%016llX\n", (unsigned long long)phase0e_irq_probe_mcause
printf "PROBE_MEPC=0x%016llX\n", (unsigned long long)phase0e_irq_probe_mepc
printf "PROBE_MTVAL=0x%016llX\n", (unsigned long long)phase0e_irq_probe_mtval
printf "PROBE_CLAIM_ID=0x%08X\n", phase0e_irq_probe_claim_id
printf "PROBE_PLIC_PENDING_BEFORE_CLAIM=0x%08X\n", phase0e_irq_probe_plic_pending_before_claim
printf "PROBE_PLIC_PENDING_AFTER_ACK=0x%08X\n", phase0e_irq_probe_plic_pending_after_ack
printf "PROBE_CEVA_STATUS_BEFORE_ACK=0x%08X\n", phase0e_irq_probe_ceva_status_before_ack
printf "PROBE_CEVA_STATUS_AFTER_ACK=0x%08X\n", phase0e_irq_probe_ceva_status_after_ack
printf "PROBE_COMPLETION_WRITTEN=0x%08X\n", phase0e_irq_probe_completion_written
printf "PROBE_HANDLER_COUNT=0x%08X\n", phase0e_irq_probe_handler_count
printf "PROBE_TARGET_COUNT=0x%08X\n", phase0e_irq_probe_target_count
printf "PROBE_DONE=0x%08X\n", phase0e_irq_probe_done
printf "PROBE_TIMEOUT=0x%08X\n", phase0e_irq_probe_timeout

set $ceva_mask_addr = 0x65000018
set $ceva_status_addr = 0x6500001c
set $plic_pending_addr = 0x0c001000
set $plic_enable_addr = 0x0c002000
set $plic_priority_addr = 0x0c000004
set $plic_threshold_addr = 0x0c200000

set $live_ceva_mask = *(unsigned int *)$ceva_mask_addr
set $live_ceva_status = *(unsigned int *)$ceva_status_addr
set $live_plic_pending = *(unsigned int *)$plic_pending_addr
set $live_plic_enable = *(unsigned int *)$plic_enable_addr
set $live_plic_priority = *(unsigned int *)$plic_priority_addr
set $live_plic_threshold = *(unsigned int *)$plic_threshold_addr

printf "LIVE_CEVA_MASK=0x%08X\n", $live_ceva_mask
printf "LIVE_CEVA_STATUS=0x%08X\n", $live_ceva_status
printf "LIVE_PLIC_PENDING=0x%08X\n", $live_plic_pending
printf "LIVE_PLIC_ENABLE=0x%08X\n", $live_plic_enable
printf "LIVE_PLIC_PRIORITY=0x%08X\n", $live_plic_priority
printf "LIVE_PLIC_THRESHOLD=0x%08X\n", $live_plic_threshold
echo LIVE_PLIC_CLAIM_COMPLETE=SKIPPED_SIDE_EFFECT\n

echo EXPECT_MAGIC=0x30454331\n
echo EXPECT_MCAUSE=0x800000000000000B\n
echo EXPECT_CLAIM_ID=0x00000001\n
echo EXPECT_CEVA_STATUS_MASK=0x00000008\n
echo EXPECT_PLIC_PENDING_MASK=0x00000002\n
echo OBSERVATION_ONLY_FIELDS=PROBE_MEPC,PROBE_MTVAL,PROBE_PLIC_PENDING_BEFORE_CLAIM,PROBE_PLIC_PENDING_AFTER_ACK,LIVE_PLIC_PENDING,PROBE_COMPLETION_WRITTEN,PROBE_TIMEOUT\n
echo HARD_PASS_FIELDS=PROBE_MAGIC,PROBE_HANDLER_COUNT,PROBE_TARGET_COUNT,PROBE_MCAUSE,PROBE_CLAIM_ID,PROBE_CEVA_STATUS_BEFORE_ACK,PROBE_CEVA_STATUS_AFTER_ACK,PROBE_DONE\n

echo \n=== done ===\n

monitor go
detach
quit