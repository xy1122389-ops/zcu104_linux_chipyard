# update_bootrom_bram.tcl
# Opens post_route.dcp, finds BootROM BRAMs, updates init values with new
# sdboot.bin, and writes a new bitstream.
#
# Usage (from Vivado): source scripts/update_bootrom_bram.tcl
# Or:  vivado -mode batch -source scripts/update_bootrom_bram.tcl

set script_dir [file dirname [info script]]
set fpga_dir   [file normalize "$script_dir/.."]

# ----- Paths -----
set cfg "chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig"
set dcp_file   "${fpga_dir}/generated-src/${cfg}/obj/post_route.dcp"
set sdboot_bin "${fpga_dir}/src/main/resources/zcu104/sdboot/build/sdboot.bin"
set bit_out    "${fpga_dir}/generated-src/${cfg}/obj/ZCU104FPGATestHarness.bit"
set bit_bak    "${bit_out}.bak.pre_autojump_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"

# ----- Sanity checks -----
if {![file exists $dcp_file]} { error "DCP not found: $dcp_file" }
if {![file exists $sdboot_bin]} { error "sdboot.bin not found: $sdboot_bin" }

puts "=== update_bootrom_bram.tcl ==="
puts "DCP:        $dcp_file"
puts "sdboot.bin: $sdboot_bin"
puts "Output bit: $bit_out"

# ----- Backup existing bitstream -----
if {[file exists $bit_out]} {
    file copy -force $bit_out $bit_bak
    puts "Backed up: $bit_bak"
}

# ----- Open checkpoint -----
puts "Opening DCP..."
open_checkpoint $dcp_file

# ----- Find BootROM BRAMs -----
# The BootROM in Chipyard is typically named *bootrom* or *rom* or *TLROM*
# Search for all RAMB cells and filter by name containing "rom" or "boot"
set all_brams [get_cells -hierarchical -filter {PRIMITIVE_TYPE =~ BMEM.*}]
puts "Total BRAM cells: [llength $all_brams]"

set rom_brams {}
foreach bram $all_brams {
    set name [get_property NAME $bram]
    # Look for bootrom/rom/bootROM/TLROM in the hierarchy
    if {[regexp -nocase {boot|rom|ROM} $name]} {
        lappend rom_brams $bram
        set type [get_property PRIMITIVE_TYPE $bram]
        puts "  ROM candidate: $name  type=$type"
    }
}

if {[llength $rom_brams] == 0} {
    puts "WARNING: No BRAM cells with 'rom'/'boot' in name found."
    puts "Listing all BRAMs for manual inspection:"
    foreach bram $all_brams {
        puts "  [get_property NAME $bram]  [get_property PRIMITIVE_TYPE $bram]"
    }
    close_design
    error "Cannot identify BootROM BRAMs. Manual intervention needed."
}

puts "\nFound [llength $rom_brams] BootROM BRAM candidate(s)."

# ----- Read sdboot.bin -----
set fd [open $sdboot_bin r]
fconfigure $fd -translation binary
set bin_data [read $fd]
close $fd
set bin_size [string length $bin_data]
puts "sdboot.bin size: $bin_size bytes"

# ----- Convert binary to init strings -----
# RAMB36E2 has 256-bit wide init strings (32 bytes per init string)
# Total: 128 INIT_xx parameters (INIT_00..INIT_7F) = 128*32 = 4096 bytes per BRAM
# RAMB18E2: 64 INIT_xx parameters = 64*32 = 2048 bytes per BRAM
#
# For a typical BootROM with 64-bit data width:
# - Each BRAM stores different bit slices of the data
# - The init values need to be assigned per-BRAM based on bit slice
#
# SIMPLER APPROACH: Use write_mem_info + updatemem
# Actually, let's generate MMI first, then use updatemem

# ----- Generate MMI -----
set mmi_file "${fpga_dir}/generated-src/${cfg}/obj/bootrom.mmi"
puts "\nGenerating MMI file..."

# Use write_mem_info to generate memory info
write_mem_info -force $mmi_file
puts "MMI written to: $mmi_file"

# ----- Close design (updatemem needs it closed) -----
close_design

# ----- Use updatemem to patch bitstream -----
# First need to identify the correct memory instance in the MMI
puts "\n=== updatemem phase ==="
puts "Reading MMI to find BootROM processor..."

# Read MMI and find the bootrom address processor
set mmi_fd [open $mmi_file r]
set mmi_content [read $mmi_fd]
close $mmi_fd

# Find address processor containing "rom" or "boot"
set rom_processors {}
set lines [split $mmi_content "\n"]
set current_proc ""
foreach line $lines {
    if {[regexp {<Processor.*Inst=\"([^\"]+)\"} $line -> inst]} {
        set current_proc $inst
    }
    if {[regexp -nocase {rom|boot} $line] && $current_proc ne ""} {
        if {[lsearch $rom_processors $current_proc] < 0} {
            lappend rom_processors $current_proc
        }
    }
}

puts "Found processors with ROM/boot references: $rom_processors"

# Try updatemem with each candidate
set success 0
foreach proc_name $rom_processors {
    puts "\nTrying updatemem with processor: $proc_name"
    set elf_file "${fpga_dir}/src/main/resources/zcu104/sdboot/build/sdboot.elf"
    if {[catch {
        exec updatemem -force \
            -meminfo $mmi_file \
            -data $elf_file \
            -bit $bit_bak \
            -proc $proc_name \
            -out $bit_out
        set success 1
        puts "SUCCESS: updatemem completed for processor $proc_name"
    } err]} {
        puts "Failed for $proc_name: $err"
    }
    if {$success} break
}

if {!$success} {
    puts "\n=== Fallback: trying all processors ==="
    # List all processors in MMI
    foreach line $lines {
        if {[regexp {<Processor.*Inst=\"([^\"]+)\"} $line -> inst]} {
            puts "  Processor: $inst"
        }
    }
    puts "\nWill try each processor..."
    foreach line $lines {
        if {[regexp {<Processor.*Inst=\"([^\"]+)\"} $line -> inst]} {
            puts "  Trying: $inst"
            if {[catch {
                exec updatemem -force \
                    -meminfo $mmi_file \
                    -data "${fpga_dir}/src/main/resources/zcu104/sdboot/build/sdboot.elf" \
                    -bit $bit_bak \
                    -proc $inst \
                    -out $bit_out
                set success 1
                puts "  SUCCESS with processor: $inst"
            } err]} {
                # continue
            }
            if {$success} break
        }
    }
}

if {$success} {
    puts "\n=== DONE ==="
    puts "New bitstream: $bit_out"
    puts "Backup:        $bit_bak"
} else {
    # Last resort: open design, directly modify INIT values
    puts "\n=== updatemem failed for all processors ==="
    puts "Falling back to direct BRAM INIT modification..."
    
    open_checkpoint $dcp_file
    
    # Re-find ROM BRAMs
    set rom_brams {}
    foreach bram [get_cells -hierarchical -filter {PRIMITIVE_TYPE =~ BMEM.*}] {
        set name [get_property NAME $bram]
        if {[regexp -nocase {boot|rom|ROM} $name]} {
            lappend rom_brams $bram
        }
    }
    
    puts "ROM BRAMs: $rom_brams"
    puts "Dumping current INIT_00 values for inspection:"
    foreach bram $rom_brams {
        set init00 [get_property INIT_00 $bram]
        puts "  [get_property NAME $bram]: INIT_00 = $init00"
    }
    
    # For now, just generate bitstream from the unmodified checkpoint
    # The user will need to manually fix the BRAM init values
    puts "\nManual BRAM update needed. See ROM BRAM names above."
    close_design
    error "Automatic BRAM update failed. Manual intervention required."
}
