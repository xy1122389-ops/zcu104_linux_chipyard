# ============================================================================
# ZCU104 + UART1 (SLIP) Bitstream Build Script
# Run from vivado_build_pkg directory:
#   vivado -nojournal -mode batch -source build_bitstream.tcl
# ============================================================================

set top "ZCU104FPGATestHarness"
set part_fpga "xczu7ev-ffvc1156-2-e"
set part_board "xilinx.com:zcu104:part0:1.1"

# Working directory
set wrkdir [file join [pwd] obj]
file mkdir $wrkdir
set ipdir [file join $wrkdir ip]
file mkdir $ipdir

# Create project
create_project -part $part_fpga -force $top
set_param messaging.defaultLimit 1000000

set_property -dict [list \
    BOARD_PART $part_board \
    TARGET_LANGUAGE {Verilog} \
    DEFAULT_LIB {xil_defaultlib} \
    IP_REPO_PATHS $ipdir \
] [current_project]

if {[get_filesets -quiet sources_1] eq ""} {
    create_fileset -srcset sources_1
}
set obj [current_fileset]

# Load all Verilog/SystemVerilog sources from vsrcs.f
set vsrc_manifest [file join [pwd] vsrcs.f]
set fp [open $vsrc_manifest r]
set files [lsearch -not -exact -all -inline [split [read $fp] "\n"] {}]
close $fp

foreach path $files {
    if {[string match {/*} $path]} {
        set full_path $path
    } else {
        set full_path [file join [pwd] $path]
    }
    if {[file exists $full_path]} {
        if {[string match {*.sv} $full_path]} {
            add_files -norecurse -fileset $obj $full_path
            set_property file_type SystemVerilog [get_files $full_path]
        } else {
            add_files -norecurse -fileset $obj $full_path
        }
    } else {
        puts "WARNING: File not found: $full_path"
    }
}

# Load IP TCL files (PLL, PS, shell overlays)
# These use $ipdir to create IPs and add constraint files
foreach tcl_file [glob -nocomplain [file join [pwd] ip-tcl *.vivado.tcl]] {
    puts "Sourcing IP TCL: $tcl_file"
    source $tcl_file
}

# AR 58526 workaround
set xci_files [get_files -all {*.xci}]
foreach xci_file $xci_files {
    set_property GENERATE_SYNTH_CHECKPOINT {false} -quiet $xci_file
}

# Generate all IP targets
set obj [get_ips -quiet]
if {$obj ne ""} {
    generate_target all $obj
    export_ip_user_files -of_objects $obj -no_script -force
}

# Read generated IP for synthesis
read_ip [glob -nocomplain -directory $ipdir [file join * {*.xci}]]

# Add board constraints (master XDC)
foreach xdc_file [glob -nocomplain [file join [pwd] constraints *.xdc]] {
    puts "Adding XDC: $xdc_file"
    add_files -fileset constrs_1 $xdc_file
}

# Set top module
set_property top $top [current_fileset]
update_compile_order -fileset sources_1

# ============================================================================
# Synthesize
# ============================================================================
puts "======== SYNTHESIS START ========"
synth_design -top $top -flatten_hierarchy rebuilt -directive Default
puts "======== SYNTHESIS DONE ========"

# Save post-synthesis checkpoint
write_checkpoint -force [file join $wrkdir post_synth.dcp]

# ============================================================================
# Optimize
# ============================================================================
opt_design -directive Explore
puts "======== OPT DONE ========"

# ============================================================================
# Place
# ============================================================================
place_design -directive Explore
puts "======== PLACE DONE ========"
write_checkpoint -force [file join $wrkdir post_place.dcp]

# ============================================================================
# Route
# ============================================================================
route_design -directive Explore
puts "======== ROUTE DONE ========"
write_checkpoint -force [file join $wrkdir post_route.dcp]

# ============================================================================
# Bitstream
# ============================================================================
# Allow bitstream generation even if reset pin has no LOC
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
write_bitstream -force [file join $wrkdir ${top}.bit]
puts "======== BITSTREAM GENERATED ========"
puts "Output: [file join $wrkdir ${top}.bit]"

# ============================================================================
# Reports
# ============================================================================
report_utilization -file [file join $wrkdir utilization.rpt]
report_timing_summary -file [file join $wrkdir timing_summary.rpt]

puts "ALL DONE. Bitstream: obj/${top}.bit"
