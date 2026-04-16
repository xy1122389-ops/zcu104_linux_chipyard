# xsdb_load_ddr.tcl — Load OpenSBI firmware + DTB into PS DDR via ARM core
#
# This script uses XSDB to download binary data through an ARM Cortex-A53 core,
# bypassing the Rocket core's J-Link debug module entirely.
# The ARM core has direct, reliable access to DDR via its own memory bus.
#
# ADDRESS MAPPING (critical!):
#   Rocket sees DDR at 0x80000000 (RISC-V ExtMem base)
#   AXI HP0 subtracts offset: Rocket_addr - 0x80000000 = PS_DDR_addr
#   ARM sees DDR at 0x00000000
#   So: fw_payload → ARM 0x00000000 (Rocket 0x80000000)
#        DTB       → ARM 0x02400000 (Rocket 0x82400000)
#
# Prerequisites:
#   - run_ps_ddr_init.sh completed (psu_init + fpga + isolation_removal)
#   - hw_server running on localhost:3121
#
# Cache note: DTB is loaded FIRST (4KB), then firmware (28MB).
# The 28MB firmware download thrashes the ARM L2 cache, evicting DTB data
# to physical DDR. This ensures Rocket (AXI HP0, non-coherent) sees correct data.

proc step {label body} {
  puts "\n==== $label ===="
  flush stdout
  if {[catch {uplevel 1 $body} err opts]} {
    puts stderr "ERROR in $label: $err"
    if {[dict exists $opts -errorinfo]} {
      puts stderr [dict get $opts -errorinfo]
    }
    flush stderr
    exit 1
  }
}

# --- File paths ---
if {$tcl_platform(platform) eq "windows"} {
  set fw_bin_orig {\\wsl.localhost\Ubuntu-22.04\root\chipyard\software\firemarshal\boards\default\firmware\opensbi\build\platform\generic\firmware\fw_payload.bin}
  set fw_bin_padded {\\wsl.localhost\Ubuntu-22.04\tmp\fw_payload_padded_0x2000.bin}
  set dtb_default {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\linux-bringup\dtb\chipyard-zcu104-fedora.dtb}
} else {
  set fw_bin_orig /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin
  set fw_bin_padded /tmp/fw_payload_padded_0x2000.bin
  set dtb_default /root/chipyard/fpga/linux-bringup/dtb/chipyard-zcu104-fedora.dtb
}

if {[info exists ::env(DTB_PATH)] && $::env(DTB_PATH) ne ""} {
  set dtb_file $::env(DTB_PATH)
} else {
  set dtb_file $dtb_default
}

if {[file exists $fw_bin_padded]} {
  set fw_bin_load $fw_bin_padded
  set fw_comp_enabled 1
} else {
  set fw_bin_load $fw_bin_orig
  set fw_comp_enabled 0
}

step "check input files" {
  if {![file exists $fw_bin_orig]} {
    error "missing fw_payload.bin: $fw_bin_orig"
  }
  if {![file exists $dtb_file]} {
    error "missing DTB: $dtb_file"
  }
  puts "fw_payload.bin (orig) = $fw_bin_orig ([file size $fw_bin_orig] bytes)"
  puts "fw_payload.bin (load) = $fw_bin_load ([file size $fw_bin_load] bytes)"
  if {$fw_comp_enabled} {
    puts "firmware compensation: enabled (padded source to cancel 0x2000 source-skip bug)"
  } else {
    puts "firmware compensation: disabled (no padded source found)"
  }
  puts "DTB            = $dtb_file ([file size $dtb_file] bytes)"
}

step "connect hw_server" {
  connect -url tcp:127.0.0.1:3121
  configparams force-mem-accesses 1
  puts "Memory access checks bypassed."
}

step "select PSU target for direct memory access" {
  # Use PSU target with mwr -force -bin for direct DDR writes via debug APB.
  # This bypasses all ARM caches, ensuring data reaches physical DDR.
  targets -set -nocase -filter {name =~ "*PSU*"}
  puts "Using PSU target for cache-bypassing DDR writes."
}

step "load fw_payload.bin -> DDR 0x00000000 (Rocket 0x80000000) -- ~51MB" {
  set fw_size [file size $fw_bin_orig]
  set fw_words [expr {($fw_size + 3) / 4}]
  puts "Loading firmware ($fw_size bytes, $fw_words words)..."
  puts "This may take a few minutes via debug transport..."
  mwr -force -bin -file $fw_bin_load 0x00000000 $fw_words
  puts "Firmware loaded."
}

# NOTE: DTB is loaded AFTER firmware so firmware write doesn't overwrite DTB.
# DTB address changed from 0x02400000 to 0x04000000 because the 51MB firmware
# extends past 0x02400000 and would overwrite DTB if loaded in the old order.
step "load DTB -> DDR 0x04000000 (Rocket 0x84000000)" {
  set dtb_size [file size $dtb_file]
  set dtb_words [expr {($dtb_size + 3) / 4}]
  puts "Loading DTB ($dtb_size bytes, $dtb_words words)..."
  mwr -force -bin -file $dtb_file 0x04000000 $dtb_words
  puts "DTB loaded."
}

step "verify key addresses (via debug APB, bypassing cache)" {
  set val0 [mrd -force -value 0x00000000]
  puts [format "  OpenSBI @ DDR 0x00000000 (Rocket 0x80000000) = 0x%08x" $val0]
  set val1 [mrd -force -value 0x00200000]
  puts [format "  Linux   @ DDR 0x00200000 (Rocket 0x80200000) = 0x%08x" $val1]
  set val2 [mrd -force -value 0x04000000]
  puts [format "  DTB     @ DDR 0x04000000 (Rocket 0x84000000) = 0x%08x" $val2]
}

step "disconnect" {
  disconnect
}

puts "\nPayload loaded to DDR via ARM core. Ready for J-Link boot."
exit
