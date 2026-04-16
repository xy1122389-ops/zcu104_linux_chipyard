# update_bootrom.tcl — One-shot: open DCP → find ROM BRAMs → write MMI → updatemem → new bitstream
#
# Run via:  vivado -mode batch -source scripts/update_bootrom.tcl

set fpga_dir   [file normalize [file dirname [info script]]/..]
set cfg        "chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig"
set gen_dir    "${fpga_dir}/generated-src/${cfg}/obj"
set dcp_file   "${gen_dir}/post_route.dcp"
set bit_orig   "${gen_dir}/ZCU104FPGATestHarness.bit"
set bit_out    "${gen_dir}/ZCU104FPGATestHarness.bit"
set bit_bak    "${bit_orig}.bak.pre_autojump_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"
set sdboot_elf "${fpga_dir}/src/main/resources/zcu104/sdboot/build/sdboot.elf"
set mmi_file   "${gen_dir}/bootrom.mmi"

puts "=== update_bootrom.tcl ==="
puts "DCP:  $dcp_file"
puts "ELF:  $sdboot_elf"

# Backup
if {[file exists $bit_orig]} {
    file copy -force $bit_orig $bit_bak
    puts "Backup: $bit_bak"
}

# Step 1: Open DCP and generate MMI
puts "\n--- Step 1: Opening DCP and writing MMI ---"
open_checkpoint $dcp_file

# List ROM BRAMs for reference
set rom_brams {}
foreach bram [get_cells -hierarchical -filter {PRIMITIVE_TYPE =~ BMEM.*}] {
    if {[regexp -nocase {boot|rom|TLROM|maskrom} [get_property NAME $bram]]} {
        lappend rom_brams $bram
        puts "  ROM BRAM: [get_property NAME $bram]"
    }
}
puts "Found [llength $rom_brams] ROM BRAM(s)"

write_mem_info -force $mmi_file
puts "MMI: $mmi_file"

# Step 2: Write bitstream from the same design (to get a clean baseline)
puts "\n--- Step 2: Writing bitstream ---"
write_bitstream -force $bit_out
close_design

# Step 3: Run updatemem
puts "\n--- Step 3: updatemem ---"

# Parse MMI to find processor name(s)
set mmi_fd [open $mmi_file r]
set mmi_text [read $mmi_fd]
close $mmi_fd

# Find all Processor instances
set procs {}
foreach {_ inst} [regexp -all -inline {<Processor\s+Inst=\"([^\"]+)\"} $mmi_text] {
    lappend procs $inst
}
puts "MMI processors: $procs"

set success 0
foreach p $procs {
    puts "  Trying updatemem -proc $p ..."
    if {![catch {
        exec updatemem -force \
            -meminfo $mmi_file \
            -data $sdboot_elf \
            -bit $bit_out \
            -proc $p \
            -out ${bit_out}.tmp
    } msg]} {
        file rename -force ${bit_out}.tmp $bit_out
        puts "  SUCCESS with processor: $p"
        set success 1
        break
    } else {
        puts "  Failed: $msg"
        file delete -force ${bit_out}.tmp
    }
}

if {!$success} {
    puts "\nERROR: updatemem failed for all processors."
    puts "Restoring backup..."
    file copy -force $bit_bak $bit_out
} else {
    puts "\n=== DONE ==="
    puts "New bitstream: $bit_out"
    puts "Backup:        $bit_bak"
}
