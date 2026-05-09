# ceva_phase0e_b2_dm_sw_irq_jlink.gdb
# Draft-only Phase 0E-B2 J-Link/GDB sequence for the single dm_sw_irq path.
#
# The wrapper script injects the proven PLIC-side defaults from generated
# collateral. This GDB file only consumes those values; it does not invent them
# locally.

set confirm off
set pagination off
set remotetimeout 15

echo \n=== Phase 0E-B2 dm_sw_irq J-Link draft ===\n

monitor halt

echo CEVA_TRIGGER_ADDR=0x65000000\n
echo CEVA_MASK_ADDR=0x65000018\n
echo CEVA_STATUS_ADDR=0x6500001C\n
echo CEVA_ACK_ADDR=0x65000020\n
echo CEVA_TRIGGER_VALUE=0x08000000\n
echo CEVA_MASK_VALUE=0x00000008\n
echo CEVA_ACK_VALUE=0x00000008\n

echo \n=== baseline_clear ===\n

monitor WriteU32 0x65000018 0x00000008
printf "PLIC_BASE=0x%08X\n", (unsigned int)$plic_base
printf "CEVA_PLIC_SOURCE_ID=%u\n", (unsigned int)$ceva_plic_source_id
printf "PLIC_PENDING_ADDR=0x%08X\n", (unsigned int)$plic_pending_addr
printf "PLIC_PENDING_BIT=%u\n", (unsigned int)$plic_pending_bit
printf "PLIC_ENABLE_ADDR=0x%08X\n", (unsigned int)$plic_enable_addr
printf "PLIC_ENABLE_BIT=%u\n", (unsigned int)$plic_enable_bit
printf "PLIC_PRIORITY_ADDR=0x%08X\n", (unsigned int)$plic_priority_addr
printf "PLIC_THRESHOLD_ADDR=0x%08X\n", (unsigned int)$plic_threshold_addr
printf "PLIC_CLAIM_COMPLETE_ADDR=0x%08X\n", (unsigned int)$plic_claim_complete_addr

monitor WriteU32 0x65000020 0x00000008

set $status_baseline = *(unsigned int *)0x6500001c
printf "STATUS_BASELINE=0x%08X\n", $status_baseline

if ($have_plic_pending)
  set $plic_pending_baseline = *(unsigned int *)$plic_pending_addr

set $plic_priority_baseline = *(unsigned int *)$plic_priority_addr
printf "PLIC_PRIORITY_BASELINE=0x%08X\n", $plic_priority_baseline

set $plic_enable_baseline = *(unsigned int *)$plic_enable_addr
printf "PLIC_ENABLE_BASELINE=0x%08X\n", $plic_enable_baseline

set $plic_threshold_baseline = *(unsigned int *)$plic_threshold_addr
printf "PLIC_THRESHOLD_BASELINE=0x%08X\n", $plic_threshold_baseline

echo PLIC_CLAIM_COMPLETE_READ=SKIPPED_SIDE_EFFECT\n
  printf "PLIC_PENDING_BASELINE=0x%08X\n", $plic_pending_baseline
else
  echo PLIC_PENDING_BASELINE=SKIPPED\n
end

echo \n=== trigger ===\n

monitor WriteU32 0x65000000 0x08000000

set $status_after_trigger = *(unsigned int *)0x6500001c
printf "STATUS_AFTER_TRIGGER=0x%08X\n", $status_after_trigger

if ($have_plic_pending)
  set $plic_pending_after_trigger = *(unsigned int *)$plic_pending_addr
  printf "PLIC_PENDING_AFTER_TRIGGER=0x%08X\n", $plic_pending_after_trigger
else
  echo PLIC_PENDING_AFTER_TRIGGER=SKIPPED\n
end

echo \n=== ack ===\n

monitor WriteU32 0x65000020 0x00000008

set $status_after_ack = *(unsigned int *)0x6500001c
printf "STATUS_AFTER_ACK=0x%08X\n", $status_after_ack

if ($have_plic_pending)
  set $plic_pending_after_ack = *(unsigned int *)$plic_pending_addr
  printf "PLIC_PENDING_AFTER_ACK=0x%08X\n", $plic_pending_after_ack
else
  echo PLIC_PENDING_AFTER_ACK=SKIPPED\n
end

echo \n=== done ===\n

monitor go
detach
quit