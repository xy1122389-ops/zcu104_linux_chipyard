set pagination off
set confirm off
set breakpoint auto-hw off

# ============================================================
# opensbi_linux_observe.gdb
# Updated 2026-03-30 for fw_payload.elf (FW_PAYLOAD + Linux Image)
#
# Key symbol addresses from current build:
#   _start            = 0x80000000
#   fw_boot_hart      = 0x80000730
#   fw_next_arg1      = 0x80000740
#   fw_next_addr      = 0x80000748
#   fw_next_mode      = 0x80000768
#   sbi_init          = 0x8000079c
#   sbi_hart_switch_mode = 0x8000b1d0
#   mret (in switch)  = 0x8000b2b2
#   _debug_stage      = 0x800200f0
#   _debug_value0..3  = 0x800200f8..0x80020110
#   _debug_last_mcause= 0x800200d8
#   _debug_last_mtval = 0x800200e0
#   _debug_last_mepc  = 0x800200e8
#   payload_bin       = 0x80200000  (Linux Image)
#
# Linux physical addresses (vmlinux virt 0xffffffff80000000 -> phys 0x80200000):
#   _start            = 0x80200000
#   _start_kernel     = 0x802010d0
#   start_kernel      = 0x80800768
#   setup_vm          = 0x808061d0
#   first BSS store   = 0x802010fe  (a3 = 0x81ad5000)
# ============================================================

python
import subprocess
import gdb

host = subprocess.check_output(
    ["bash", "-lc", "ip route | awk '/default/ {print $3; exit}'"],
    text=True,
).strip()
if not host:
    host = "172.19.128.1"
gdb.write(f"[info] Connecting to J-Link GDB Server at {host}:2331\n")
gdb.execute(f"target remote {host}:2331")
gdb.execute("add-symbol-file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf 0x80000000")
gdb.execute("add-symbol-file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux 0x80200000")
end

monitor halt

# --- OpenSBI stage breakpoints ---

define bopensbi
  delete breakpoints
  b *0x80000000
  continue
end
document bopensbi
Break at OpenSBI _start (0x80000000)
end

define bboot_hart
  delete breakpoints
  b *0x80000730
  continue
end
document bboot_hart
Break at fw_boot_hart (0x80000730)
end

define bnext_arg1
  delete breakpoints
  b *0x80000740
  continue
end
document bnext_arg1
Break at fw_next_arg1 (0x80000740)
end

define bopensbi_init
  delete breakpoints
  b *0x8000079c
  continue
end
document bopensbi_init
Break at sbi_init (0x8000079c)
end

define bopensbi_next
  delete breakpoints
  b *0x80000748
  continue
end
document bopensbi_next
Break at fw_next_addr (0x80000748)
end

define bswitchmode
  delete breakpoints
  b *0x8000b1d0
  continue
end
document bswitchmode
Break at sbi_hart_switch_mode entry (0x8000b1d0)
end

# Break right before mret - this is the most critical observation point
define bmret
  delete breakpoints
  b *0x8000b2b2
  continue
end
document bmret
Break at mret instruction inside sbi_hart_switch_mode (0x8000b2b2).
At this point: a0=hartid, a1=dtb_addr, mepc=Linux entry.
Use 'pmret' to dump pre-mret state, then 'stepi' to enter Linux.
end

# --- Linux stage breakpoints ---

define bkernel_entry
  delete breakpoints
  b *0x80200000
  continue
end
document bkernel_entry
Break at Linux Image _start (0x80200000) - the MZ header entry
end

define bkernel_head
  delete breakpoints
  b *0x802010d0
  continue
end
document bkernel_head
Break at _start_kernel (0x802010d0) - real Linux init code
end

define bkernel_bss
  delete breakpoints
  b *0x802010fe
  continue
end
document bkernel_bss
Break at first BSS store (sd zero, 0(a3)) at 0x802010fe.
a3 should be 0x81ad5000. If this faults, PMP is not configured correctly.
end

define bsetup_vm
  delete breakpoints
  b *0x808061d0
  continue
end
document bsetup_vm
Break at setup_vm (physical 0x808061d0)
end

define bstart_kernel
  delete breakpoints
  b *0x80800768
  continue
end
document bstart_kernel
Break at start_kernel (physical 0x80800768)
end

# --- Diagnostic commands ---

define pkernel
  echo --- current pc and next 10 instructions ---\n
  info reg pc
  x/10i $pc
end

define popensbistate
  echo --- _relocate_lottery / _boot_status ---\n
  x/4gx 0x800200b8
  echo --- key regs ---\n
  info reg a0 a1 a2 sp ra pc
end

define ptrapinfo
  echo --- _debug_last_mcause / mtval / mepc ---\n
  echo mcause: \n
  x/1gx 0x800200d8
  echo mtval:  \n
  x/1gx 0x800200e0
  echo mepc:   \n
  x/1gx 0x800200e8
end

define pdebugstage
  echo --- _debug_stage / value0..3 ---\n
  echo stage:  \n
  x/1gx 0x800200f0
  echo value0: \n
  x/1gx 0x800200f8
  echo value1: \n
  x/1gx 0x80020100
  echo value2: \n
  x/1gx 0x80020108
  echo value3: \n
  x/1gx 0x80020110
end

# Dump full state right before mret
define pmret
  echo === PRE-MRET STATE DUMP ===\n
  echo --- regs ---\n
  info reg a0 a1 a2 pc sp ra
  echo --- CSRs (via monitor) ---\n
  echo mstatus:\n
  monitor reg mstatus
  echo mepc:\n
  monitor reg mepc
  echo mtvec:\n
  monitor reg mtvec
  echo medeleg:\n
  monitor reg medeleg
  echo mideleg:\n
  monitor reg mideleg
  echo satp:\n
  monitor reg satp
  echo stvec:\n
  monitor reg stvec
  echo --- PMP regs ---\n
  monitor reg pmpcfg0
  monitor reg pmpaddr0
  monitor reg pmpaddr1
  monitor reg pmpaddr2
  monitor reg pmpaddr3
  echo --- breadcrumbs ---\n
  pdebugstage
  echo --- trap info ---\n
  ptrapinfo
  echo --- payload first 4 instructions ---\n
  x/4i 0x80200000
  echo === END PRE-MRET STATE ===\n
end

# Dump PMP configuration in detail
define ppmp
  echo === PMP CONFIGURATION ===\n
  echo pmpcfg0:\n
  monitor reg pmpcfg0
  echo pmpcfg2:\n
  monitor reg pmpcfg2
  echo pmpaddr0:\n
  monitor reg pmpaddr0
  echo pmpaddr1:\n
  monitor reg pmpaddr1
  echo pmpaddr2:\n
  monitor reg pmpaddr2
  echo pmpaddr3:\n
  monitor reg pmpaddr3
  echo pmpaddr4:\n
  monitor reg pmpaddr4
  echo pmpaddr5:\n
  monitor reg pmpaddr5
  echo pmpaddr6:\n
  monitor reg pmpaddr6
  echo pmpaddr7:\n
  monitor reg pmpaddr7
  echo === Note: If no PMP entry covers 0x80000000-0x82000000 with RWX for S-mode,\n
  echo    Linux will Store Access Fault on first write. ===\n
end

# Verify memory contents at key load points
define pverify
  echo === MEMORY VERIFICATION ===\n
  echo OpenSBI _start (expect: 0x0e976f05 from fw_payload.bin):\n
  x/1wx 0x80000000
  echo Linux Image header (expect: 0x106f5a4d = MZ + j _start_kernel):\n
  x/2wx 0x80200000
  echo DTB magic (expect: 0xedfe0dd0 = FDT_MAGIC LE):\n
  x/1wx 0x82400000
  echo === END VERIFY ===\n
end

define recleanopensbi
  echo --- Resetting OpenSBI state and registers ---\n
  set {long long}0x800200b8 = 0
  set {long long}0x800200c0 = 0
  set {long long}0x800200d8 = 0
  set {long long}0x800200e0 = 0
  set {long long}0x800200e8 = 0
  set {long long}0x800200f0 = 0
  set {long long}0x800200f8 = 0
  set {long long}0x80020100 = 0
  set {long long}0x80020108 = 0
  set {long long}0x80020110 = 0
  set $a0 = 0
  set $a1 = 0x82400000
  set $a2 = 0
  set $pc = 0x80000000
  echo Ready: pc=0x80000000 a0=0 a1=0x82400000\n
end

define bbootwait
  delete breakpoints
  b *0x80000418
  continue
end

define bhang
  delete breakpoints
  b *0x800004e8
  continue
end

# --- Full automated walk: OpenSBI -> Linux ---
# Steps through each major stage, collecting diagnostics at each

define walk_opensbi_to_linux
  echo === WALK: OpenSBI -> Linux kernel entry ===\n
  echo --- Diagnostic: 3x stepi from _start ---\n
  info reg pc
  stepi
  info reg pc
  stepi
  info reg pc
  stepi
  info reg pc
  echo --- Step 1: Run to sbi_init (software bkpt) ---\n
  delete breakpoints
  b *0x8000079c
  continue
  pdebugstage
  echo --- Step 2: Run to sbi_hart_switch_mode ---\n
  delete breakpoints
  b *0x8000b1d0
  continue
  pdebugstage
  echo --- Step 3: Run to mret ---\n
  delete breakpoints
  b *0x8000b2b2
  continue
  pmret
  echo --- Step 4: Single-step into Linux _start ---\n
  stepi
  echo --- Landed at: ---\n
  info reg pc
  x/4i $pc
  echo --- Step 5: Run to _start_kernel ---\n
  delete breakpoints
  b *0x802010d0
  continue
  pkernel
  echo --- Step 6: Run to first BSS store ---\n
  delete breakpoints
  b *0x802010fe
  continue
  echo --- About to store zero to BSS. a3 = ---\n
  info reg a3
  echo --- Step 7: Single-step BSS store ---\n
  stepi
  echo --- If we reach here, the first store succeeded! ---\n
  pkernel
  echo === WALK COMPLETE ===\n
end

echo \n
echo ====================================================\n
echo  OpenSBI -> Linux observe script loaded (2026-03-30)\n
echo  FW_PAYLOAD build with embedded Linux Image\n
echo ====================================================\n
echo \n
echo Stage breakpoints:\n
echo   bopensbi      - OpenSBI _start       (0x80000000)\n
echo   bboot_hart    - fw_boot_hart          (0x80000730)\n
echo   bnext_arg1    - fw_next_arg1          (0x80000740)\n
echo   bopensbi_init - sbi_init              (0x8000079c)\n
echo   bopensbi_next - fw_next_addr          (0x80000748)\n
echo   bswitchmode   - sbi_hart_switch_mode  (0x8000b1d0)\n
echo   bmret         - mret instruction      (0x8000b2b2)\n
echo \n
echo Linux breakpoints:\n
echo   bkernel_entry - Linux _start          (0x80200000)\n
echo   bkernel_head  - _start_kernel         (0x802010d0)\n
echo   bkernel_bss   - first BSS sd          (0x802010fe)\n
echo   bsetup_vm     - setup_vm              (0x808061d0)\n
echo   bstart_kernel - start_kernel          (0x80800768)\n
echo \n
echo Diagnostics:\n
echo   pkernel       - pc + next 10 instr\n
echo   popensbistate - relocate/boot state + regs\n
echo   ptrapinfo     - last mcause/mtval/mepc\n
echo   pdebugstage   - breadcrumb stage + values\n
echo   pmret         - full pre-mret state dump (regs+CSRs+PMP+payload)\n
echo   ppmp          - PMP register dump\n
echo   pverify       - verify memory at key addresses\n
echo \n
echo Actions:\n
echo   recleanopensbi     - zero state, set pc=0x80000000 a0=0 a1=dtb\n
echo   walk_opensbi_to_linux - automated walk through all stages\n
echo   bbootwait          - _wait_for_boot_hart\n
echo   bhang              - _start_hang\n
