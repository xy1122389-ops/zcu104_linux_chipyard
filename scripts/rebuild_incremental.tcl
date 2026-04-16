# Incremental Vivado rebuild for BootROM-only change (TLROM.sv)
# Usage: vivado -nojournal -mode batch -source rebuild_incremental.tcl

set scriptdir [file normalize "//wsl.localhost/Ubuntu-22.04/root/chipyard/fpga/fpga-shells/xilinx/common/tcl"]
set builddir  [file normalize "//wsl.localhost/Ubuntu-22.04/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig"]

set top        "ZCU104FPGATestHarness"
set board      "zcu104"
set part_fpga  "xczu7ev-ffvc1156-2-e"
set part_board "xilinx.com:zcu104:part0:1.1"

set wrkdir     [file join $builddir obj]
set ipdir      [file join $wrkdir ip]

# Paths to reference checkpoints for incremental compile
set ref_synth  [file join $wrkdir post_synth.dcp]
set ref_route  [file join $wrkdir post_route.dcp]

# Source files
set vsrc_manifest [file join $builddir "vsrcs_win.f"]
set boarddir [file join [file dirname $scriptdir] $board]
set constraintsdir [file join $boarddir constraints]
set srcdir [file join [file dirname $scriptdir] vsrc]
set commondir [file dirname $scriptdir]

# IP Vivado TCL scripts
set ip_vivado_tcls [list \
  [file join $builddir "chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig.harnessSysPLL.vivado.tcl"] \
  [file join $builddir "chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig.shell.vivado.tcl"] \
  [file join $builddir "chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig.zcu104ps.vivado.tcl"] \
]

puts "=== Incremental BootROM Rebuild ==="
puts "Build dir: $builddir"
puts "Ref synth: $ref_synth"
puts "Ref route: $ref_route"

# --- Include helper functions ---
source [file join $scriptdir "util.tcl"]

# --- Create project ---
create_project -part $part_fpga -force $top
set_param messaging.defaultLimit 1000000
set_property -dict [list \
  BOARD_PART $part_board \
  TARGET_LANGUAGE {Verilog} \
  DEFAULT_LIB {xil_defaultlib} \
  IP_REPO_PATHS $ipdir \
] [current_project]

# --- Read source files ---
if {[get_filesets -quiet sources_1] eq ""} {
  create_fileset -srcset sources_1
}
set obj [current_fileset]

# Load vsrc manifest
set fp [open $vsrc_manifest r]
set files [lsearch -not -exact -all -inline [split [read $fp] "\n"] {}]
set relative_files {}
foreach path $files {
  if {[string match {/*} $path]} {
    lappend relative_files $path
  } elseif {![string match {#*} $path]} {
    lappend relative_files [file join [file dirname $vsrc_manifest] $path]
  }
}
add_files -norecurse -fileset $obj {*}$relative_files
close $fp

# --- Generate IPs ---
foreach ip_vivado_tcl $ip_vivado_tcls {
  source $ip_vivado_tcl
}
set boardiptcl [file join $boarddir tcl ip.tcl]
if {[file exists $boardiptcl]} {
  source $boardiptcl
}

# AR 58526
set xci_files [get_files -all {*.xci}]
foreach xci_file $xci_files {
  set_property GENERATE_SYNTH_CHECKPOINT {false} -quiet $xci_file
}
set ipobj [get_ips]
if {$ipobj ne ""} {
  generate_target all $ipobj
  export_ip_user_files -of_objects $ipobj -no_script -force
}

# Read IP XCI files
read_ip [glob -nocomplain -directory $ipdir [file join * {*.xci}]]

# Set include dirs
set property_include_dirs [get_property include_dirs [current_fileset]]
set ip_include_dirs [concat $property_include_dirs [findincludedir $ipdir "*.vh"]]
set ip_include_dirs [concat $ip_include_dirs [findincludedir $srcdir "*.h"]]
set ip_include_dirs [concat $ip_include_dirs [findincludedir $srcdir "*.vh"]]

# --- Read constraints ---
if {[get_filesets -quiet constrs_1] eq ""} {
  create_fileset -constrset constrs_1
}
set cobj [current_fileset -constrset]
add_files -quiet -norecurse -fileset $cobj [lsort [glob -directory $constraintsdir -nocomplain {*.tcl}]]
add_files -quiet -norecurse -fileset $cobj [lsort [glob -directory $constraintsdir -nocomplain {*.xdc}]]

# === SYNTHESIS ===
puts "=== Starting Synthesis ==="
synth_design -top $top -flatten_hierarchy rebuilt
write_checkpoint -force [file join $wrkdir post_synth]

# === OPTIMIZATION ===
puts "=== Optimization ==="
opt_design -directive Explore
write_checkpoint -force [file join $wrkdir post_opt]

# === PLACEMENT with incremental reference ===
puts "=== Placement ==="
if {[file exists $ref_route]} {
  puts "Reading incremental placement reference: $ref_route"
  read_checkpoint -incremental $ref_route
}
place_design -directive Explore
phys_opt_design -directive Explore
power_opt_design
write_checkpoint -force [file join $wrkdir post_place]

# === ROUTING ===
puts "=== Routing ==="
route_design -directive Explore
phys_opt_design -directive Explore
write_checkpoint -force [file join $wrkdir post_route]

# === BITSTREAM ===
puts "=== Writing Bitstream ==="
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
write_bitstream -force [file join $wrkdir "${top}.bit"]
write_sdf -force [file join $wrkdir "${top}.sdf"]

puts "=== DONE ==="
puts "Bitstream: [file join $wrkdir ${top}.bit]"
