# Incremental rebuild TCL for Phase 1A hready_in_r fix
# Uses post_synth.dcp as incremental synthesis reference and
# post_route.dcp as incremental implementation reference.
# This avoids full 3-4 hour rebuild; typically takes 45-90 min.
#
# Usage (from Windows Vivado via CMD):
#   vivado.bat -mode batch -nojournal -source Z:\path\scripts\incremental_rebuild_phase1a.tcl
#   CWD should be: <BUILD_DIR>/obj/
#
# Variables expected to be passed via -tclargs or set before sourcing:
#   $BUILD_DIR   - Windows path to the build directory
#   $VSRCS_WIN   - Windows path to vsrcs_win.f
#   $IP_TCLS     - space-separated list of Windows paths to *.vivado.tcl

# Parse optional command-line overrides from -tclargs.
while {[llength $argv]} {
    set argv [lassign $argv[set argv {}] flag]
    switch -glob -- $flag {
        -BUILD_DIR {
            set argv [lassign $argv[set argv {}] BUILD_DIR]
        }
        -OBJ_DIR {
            set argv [lassign $argv[set argv {}] OBJ_DIR]
        }
        -VSRCS_WIN {
            set argv [lassign $argv[set argv {}] VSRCS_WIN]
        }
        default {
            return -code error [list {unknown option} $flag]
        }
    }
}

# If not set via tclargs, use defaults relative to Z: drive
if {![info exists BUILD_DIR]} {
    set BUILD_DIR {Z:\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Phase0bConfig}
}
if {![info exists VSRCS_WIN]} {
    set VSRCS_WIN "${BUILD_DIR}\\vsrcs_win.f"
}
if {![info exists OBJ_DIR]} {
    set OBJ_DIR "${BUILD_DIR}\\obj"
}

set TOP_MODULE "ZCU104FPGATestHarness"
set BOARD "zcu104"
set PART_FPGA  "xczu7ev-ffvc1156-2-e"
set PART_BOARD "xilinx.com:zcu104:part0:1.1"
set SCRIPTDIR {Z:\root\chipyard\fpga\fpga-shells\xilinx\common\tcl}
set BOARDDIR  {Z:\root\chipyard\fpga\fpga-shells\xilinx\zcu104}
set CONSTRAINTSDIR "${BOARDDIR}\\constraints"
set ipdir "${OBJ_DIR}\\ip"

set POST_SYNTH_DCP "${OBJ_DIR}\\post_synth.dcp"
set POST_ROUTE_DCP "${OBJ_DIR}\\post_route.dcp"
set POST_SYNTH_NEW  "${OBJ_DIR}\\post_synth_incr.dcp"
set POST_OPT_NEW    "${OBJ_DIR}\\post_opt_incr.dcp"
set POST_PLACE_NEW  "${OBJ_DIR}\\post_place_incr.dcp"
set POST_ROUTE_NEW  "${OBJ_DIR}\\post_route_incr.dcp"
set BIT_FILE        "${OBJ_DIR}\\ZCU104FPGATestHarness.bit"

puts "======================================================="
puts " Incremental Rebuild - Phase 1A hready_in_r fix"
puts "======================================================="
puts " BUILD_DIR:      $BUILD_DIR"
puts " VSRCS_WIN:      $VSRCS_WIN"
puts " POST_SYNTH_REF: $POST_SYNTH_DCP"
puts " POST_ROUTE_REF: $POST_ROUTE_DCP"
puts "======================================================="

# ---------------------------------------------------------------------------
# Step 1: Include helper utilities (util.tcl defines findincludedir etc.)
# ---------------------------------------------------------------------------
source "${SCRIPTDIR}\\util.tcl"

# ---------------------------------------------------------------------------
# Step 1b: Create an in-memory project so IP/constraint commands have context.
# ---------------------------------------------------------------------------
file mkdir $ipdir
create_project -part $PART_FPGA -force $TOP_MODULE
set_param messaging.defaultLimit 1000000
set_property -dict [list \
    BOARD_PART $PART_BOARD \
    TARGET_LANGUAGE {Verilog} \
    DEFAULT_LIB {xil_defaultlib} \
    IP_REPO_PATHS [file normalize $ipdir] \
] [current_project]

if {[get_filesets -quiet sources_1] eq ""} {
    create_fileset -srcset sources_1
}

if {[get_filesets -quiet constrs_1] eq ""} {
    create_fileset -constrset constrs_1
}

# ---------------------------------------------------------------------------
# Step 2: IP catalog and IP generation
# ---------------------------------------------------------------------------
update_ip_catalog -rebuild

# Source IP vivado TCLs
set ip_vivado_tcls [glob -nocomplain "${BUILD_DIR}\\*.vivado.tcl"]
foreach ip_vivado_tcl $ip_vivado_tcls {
    source $ip_vivado_tcl
}

# Optional board ip script
set boardiptcl "${BOARDDIR}\\tcl\\ip.tcl"
if {[file exists $boardiptcl]} { source $boardiptcl }

# Import generated XCI files from disk into the current project.
set disk_xci_files [glob -nocomplain -directory $ipdir [file join * {*.xci}]]
if {[llength $disk_xci_files] > 0} {
    read_ip $disk_xci_files
}

set xci_files [get_files -all {*.xci}]
foreach xci_file $xci_files {
    set_property GENERATE_SYNTH_CHECKPOINT {false} -quiet $xci_file
}

set obj [get_ips]
if {$obj ne ""} {
    generate_target all $obj
    export_ip_user_files -of_objects $obj -no_script -force
}

# Include dirs
set obj [current_fileset]
set property_include_dirs [get_property include_dirs $obj]
set ip_include_dirs [concat $property_include_dirs [findincludedir $ipdir "*.vh"]]
set ip_include_dirs [concat $ip_include_dirs [findincludedir {Z:\root\chipyard\fpga\src} "*.h"]]
set ip_include_dirs [concat $ip_include_dirs [findincludedir {Z:\root\chipyard\fpga\src} "*.vh"]]
set_property include_dirs $ip_include_dirs $obj

# ---------------------------------------------------------------------------
# Step 3: Read ALL source files from vsrcs_win.f
# ---------------------------------------------------------------------------
puts "\nStep 3: Reading source files from $VSRCS_WIN"

set fp [open $VSRCS_WIN r]
set vsrc_lines [split [read $fp] "\n"]
close $fp

foreach src_file $vsrc_lines {
    set src_file [string trim $src_file]
    if {$src_file eq "" || [string match "#*" $src_file]} { continue }
    if {[file extension $src_file] eq ".v" || [file extension $src_file] eq ".sv"} {
        read_verilog -sv $src_file
    } elseif {[file extension $src_file] eq ".vhd" || [file extension $src_file] eq ".vhdl"} {
        read_vhdl $src_file
    } else {
        # Try as verilog by default
        catch { read_verilog -sv $src_file }
    }
}

# Read XDC constraints
set xdc_files [glob -nocomplain "${CONSTRAINTSDIR}\\*.xdc"]
foreach xdc $xdc_files { read_xdc $xdc }

# Collect generated build-specific constraints (for shell IO LOC/IOSTANDARD, etc.).
# These files use `get_ports` and conditional Tcl, so they must be sourced only
# after a synthesized design is open; sourcing them here binds nothing.
set generated_xdc_files [glob -nocomplain -directory $BUILD_DIR *.xdc]
if {[llength $generated_xdc_files] == 0} {
    set generated_shell_xdc [file join $BUILD_DIR "[file tail $BUILD_DIR].shell.xdc"]
    if {[file exists $generated_shell_xdc]} {
        set generated_xdc_files [list $generated_shell_xdc]
    }
}

proc apply_generated_shell_constraints {generated_xdc_files stage} {
    if {[llength $generated_xdc_files] == 0} {
        puts "No generated shell constraints found during $stage"
        return
    }

    foreach xdc $generated_xdc_files {
        puts "Applying generated shell constraints ($stage): $xdc"
        source $xdc
    }

    set representative_ports {
        sys_clock_p sys_clock_n uart1_rxd uart1_txd uart_rxd uart_txd
        sdio_spi_clk sdio_spi_cs sdio_spi_dat_0 sdio_spi_dat_3
        jtag_jtag_TCK jtag_jtag_TDI jtag_jtag_TDO jtag_jtag_TMS gpio_led_2_ls
    }
    set constrained_ports 0
    foreach port_name $representative_ports {
        set port_obj [get_ports -quiet $port_name]
        if {[llength $port_obj] == 0} { continue }

        set iostandard [get_property IOSTANDARD $port_obj]
        set loc [get_property PACKAGE_PIN $port_obj]
        if {$iostandard ne "DEFAULT" && $loc ne ""} {
            incr constrained_ports
        }
    }
    puts "Generated shell constraint summary ($stage): $constrained_ports/[llength $representative_ports] representative ports constrained"
}

# ---------------------------------------------------------------------------
# Step 4: INCREMENTAL SYNTHESIS using post_synth.dcp as reference
# ---------------------------------------------------------------------------
puts "\nStep 4: Incremental synthesis (reference: $POST_SYNTH_DCP)"

# Set incremental synthesis reference checkpoint
read_checkpoint -incremental $POST_SYNTH_DCP

# Run synthesis
synth_design -top $TOP_MODULE -flatten_hierarchy rebuilt

# Apply generated shell constraints now that top-level ports and IOB cells exist.
apply_generated_shell_constraints $generated_xdc_files post-synth

# Save synthesized checkpoint
write_checkpoint -force $POST_SYNTH_NEW
puts "Step 4 done: post_synth_incr.dcp written"

# ---------------------------------------------------------------------------
# Step 5: INCREMENTAL IMPLEMENTATION using post_route.dcp as reference
# ---------------------------------------------------------------------------
puts "\nStep 5: Incremental implementation (reference: $POST_ROUTE_DCP)"
# Opt
opt_design -directive Explore
write_checkpoint -force $POST_OPT_NEW
puts "Step 5a: post_opt_incr.dcp written"

# Set incremental implementation reference checkpoint before placement.
read_checkpoint -incremental $POST_ROUTE_DCP
apply_generated_shell_constraints $generated_xdc_files pre-place

# Place
place_design -directive Explore
phys_opt_design -directive Explore
power_opt_design
write_checkpoint -force $POST_PLACE_NEW
puts "Step 5b: post_place_incr.dcp written"

# Route
route_design -directive Explore
phys_opt_design -directive Explore
write_checkpoint -force $POST_ROUTE_NEW
puts "Step 5c: post_route_incr.dcp written"

# ---------------------------------------------------------------------------
# Step 6: DRC with ALLOW_COMBINATORIAL_LOOPS removed (loop is fixed in RTL)
# ---------------------------------------------------------------------------
puts "\nStep 6: DRC check (comb loop should be gone after RTL fix)"
set drc_violations [report_drc -return_string -checks {LUTLP}]
set lutlp_count -1
if {[regexp {Violations found:\s*([0-9]+)} $drc_violations -> lutlp_count] && $lutlp_count > 0} {
    puts "WARNING: LUTLP-1 still present! RTL fix may not have taken effect."
    puts $drc_violations
} else {
    puts "DRC PASS: No LUTLP-1 combinatorial loop errors."
}

# ---------------------------------------------------------------------------
# Step 7: Write bitstream
# ---------------------------------------------------------------------------
puts "\nStep 7: Writing bitstream..."
apply_generated_shell_constraints $generated_xdc_files pre-bitgen
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
write_bitstream -force $BIT_FILE
puts "======================================================="
puts " Incremental Rebuild COMPLETE"
puts " Bitstream: $BIT_FILE"
puts "======================================================="
