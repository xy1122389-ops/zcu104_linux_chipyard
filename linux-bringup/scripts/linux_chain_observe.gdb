set pagination off
set confirm off

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
end

monitor halt

define blstart
  delete breakpoints
  hbreak linux_chain_start_marker
  continue
end

define blpayload
  delete breakpoints
  hbreak linux_payload_stage_marker
  continue
end

define blkernel
  delete breakpoints
  hbreak linux_kernel_stage_marker
  continue
end

define bldtb
  delete breakpoints
  hbreak linux_dtb_stage_marker
  continue
end

define bljump
  delete breakpoints
  hbreak linux_jump_stage_marker
  continue
end

define blpaydone
  delete breakpoints
  hbreak payload_load_done_marker
  continue
end

define blkerneldone
  delete breakpoints
  hbreak kernel_load_done_marker
  continue
end

define bldtbdone
  delete breakpoints
  hbreak dtb_load_done_marker
  continue
end

define blready
  delete breakpoints
  hbreak linux_ready_to_jump_marker
  continue
end

define bljumpdone
  delete breakpoints
  hbreak linux_jump_taken_marker
  continue
end

define bljumpblock
  delete breakpoints
  hbreak linux_jump_blocked_marker
  continue
end

define blidle
  delete breakpoints
  hbreak linux_count_loop_marker
  continue
end

define pcur
  info reg pc
  x/10i $pc
end

define pmanifest
  x/10gx 0x803df000
end

echo Linux front-chain observe script loaded.\n
echo Commands:\n
echo   blstart   - break at linux chain start marker\n
echo   blpayload - break before payload stage\n
echo   blkernel  - break before kernel stage\n
echo   bldtb     - break before dtb stage\n
echo   bljump    - break before jump linux entry marker\n
echo   blpaydone - break after payload ready is observed\n
echo   blkerneldone - break after kernel ready is observed\n
echo   bldtbdone - break after dtb ready is observed\n
echo   blready   - break when front-chain reports ready_to_jump\n
echo   bljumpdone - reserved marker for future real jump\n
echo   bljumpblock - break when front-chain blocks jump\n
echo   blidle    - break in linux idle heartbeat loop\n
echo   pcur      - show current pc and 10 instructions\n
echo   pmanifest - dump front-chain manifest block at 0x803df000\n
