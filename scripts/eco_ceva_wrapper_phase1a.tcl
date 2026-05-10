# eco_ceva_wrapper_phase1a.tcl
# ECO flow: synthesize ONLY the CEVA wrapper (no FPU = no deadlock),
# then replace its cells in the existing post_route.dcp and regenerate bitstream.
#
# Avoids full re-synthesis which deadlocks on Berkeley HardFloat in Vivado 2021.2.

set BUILD_DIR  {Z:\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Phase0bConfig}
set OBJ_DIR    [file join $BUILD_DIR obj]
set GEN_COL    [file join $BUILD_DIR gen-collateral]

set WRAPPER_NAME rw_dm_top_phase0b_real_wrapper
set WRAPPER_V    [file join $GEN_COL ${WRAPPER_NAME}.v]
set OOC_DIR      [file join $OBJ_DIR eco_ooc_wrapper]
set OOC_DCP      [file join $OBJ_DIR eco_wrapper_ooc.dcp]
set ECO_ROUTE    [file join $OBJ_DIR post_route_eco.dcp]
set BIT_FILE     [file join $OBJ_DIR ZCU104FPGATestHarness.bit]
set POST_ROUTE   [file join $OBJ_DIR post_route.dcp]

puts "======================================================="
puts " Phase 1A ECO: CEVA wrapper hready_in_r fix"
puts "======================================================="
puts " BUILD_DIR:    $BUILD_DIR"
puts " WRAPPER_V:    $WRAPPER_V"
puts " POST_ROUTE:   $POST_ROUTE"
puts " OOC_DCP:      $OOC_DCP"
puts " BIT_FILE:     $BIT_FILE"
puts "======================================================="

# -------------------------------------------------------
# Step 1: OOC synthesis of CEVA wrapper only
#   The wrapper has NO FPU logic -> no deadlock risk
# -------------------------------------------------------
puts "Step 1/4: OOC synthesis of $WRAPPER_NAME ..."
file mkdir $OOC_DIR
create_project -force eco_ooc $OOC_DIR -part xczu7ev-ffvc1156-2-e
set_param synth.maxThreads 1
set_param general.maxThreads 1

# Read all CEVA files in correct order (from generated filelist, ordered per rw_dm_top_rtl_files.list)
# This includes: overrides -> user_defines -> defines -> IP files -> wrapper (TOP)
set FILELIST_TCL {Z:\root\chipyard\fpga\scripts\ceva_ooc_filelist.tcl}
puts "Reading CEVA files via ordered filelist: $FILELIST_TCL"
source $FILELIST_TCL

set_property top $WRAPPER_NAME [current_fileset]
synth_design -mode out_of_context -top $WRAPPER_NAME -flatten_hierarchy rebuilt
write_checkpoint -force $OOC_DCP
close_project
puts "Step 1/4 OOC synthesis done: $OOC_DCP"

# -------------------------------------------------------
# Step 2: Open existing routed design
# -------------------------------------------------------
puts "Step 2/4: Opening post_route.dcp ..."
open_checkpoint $POST_ROUTE

# Find the CEVA wrapper instance in the hierarchy
set wrapper_cells [get_cells -hierarchical -filter "REF_NAME == $WRAPPER_NAME"]
if {[llength $wrapper_cells] == 0} {
    set wrapper_cells [get_cells -hierarchical -filter "ORIG_REF_NAME == $WRAPPER_NAME"]
}
if {[llength $wrapper_cells] == 0} {
    puts "ERROR: Could not find cell with REF_NAME == $WRAPPER_NAME"
    puts "Available top-level cells:"
    foreach c [get_cells] { puts "  $c" }
    exit 1
}
set wrapper_cell [lindex $wrapper_cells 0]
puts "Found wrapper cell: $wrapper_cell"

# -------------------------------------------------------
# Step 3: ECO - replace wrapper cells with new OOC netlist
# -------------------------------------------------------
puts "Step 3/4: ECO replacing wrapper cells with new OOC checkpoint ..."

# Must convert the cell to black-box BEFORE read_checkpoint -cell
# (Vivado 12-12243: read_checkpoint -cell only works on black-box instances)
puts "Converting $wrapper_cell to black-box for ECO replacement ..."
update_design -black_box -cells $wrapper_cell
puts "Black-box done, now reading new OOC DCP into cell ..."
read_checkpoint -cell $wrapper_cell $OOC_DCP

# Incremental placement (only changed area needs re-placement)
puts "Running place_design -directive RefinePlacement ..."
place_design -directive RefinePlacement
puts "Running phys_opt_design ..."
phys_opt_design -directive AggressiveExplore
puts "Running route_design ..."
route_design -directive AggressiveExplore -tns_cleanup

write_checkpoint -force $ECO_ROUTE
puts "Step 3/4 ECO place+route done"

# -------------------------------------------------------
# Step 4: Write bitstream
# -------------------------------------------------------
puts "Step 4/4: Writing bitstream ..."
write_bitstream -force -file $BIT_FILE
puts "======================================================="
puts " ECO COMPLETE: $BIT_FILE"
puts "======================================================="
