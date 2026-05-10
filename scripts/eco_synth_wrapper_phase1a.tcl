# eco_synth_wrapper_phase1a.tcl
# ECO at SYNTHESIS CHECKPOINT level:
#   - open post_synth.dcp (synthesized May 10, old wrapper without hready_in_r)
#   - black-box the old wrapper cell
#   - inject new OOC-synthesized wrapper (with hready_in_r fix)
#   - re-run opt+place+route+bitstream (~25 min, no synthesis deadlock risk)
#
# REASON: ECO on post_route.dcp fails with 493-port mismatch (implementation pins).
#         ECO on post_synth.dcp uses RTL module ports (13 ports) — should match.

set BUILD_DIR  {Z:\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Phase0bConfig}
set OBJ_DIR    [file join $BUILD_DIR obj]

set WRAPPER_NAME rw_dm_top_phase0b_real_wrapper
set OOC_DCP      [file join $OBJ_DIR eco_wrapper_ooc.dcp]
set POST_SYNTH   [file join $OBJ_DIR post_synth.dcp]
set ECO_SYNTH    [file join $OBJ_DIR post_synth_eco.dcp]
set ECO_OPT      [file join $OBJ_DIR post_opt_eco.dcp]
set ECO_PLACE    [file join $OBJ_DIR post_place_eco.dcp]
set ECO_ROUTE    [file join $OBJ_DIR post_route_eco.dcp]
set BIT_FILE     [file join $OBJ_DIR ZCU104FPGATestHarness.bit]

puts "======================================================="
puts " Phase 1A ECO at SYNTHESIS level: hready_in_r fix"
puts "======================================================="
puts " POST_SYNTH: $POST_SYNTH"
puts " OOC_DCP:   $OOC_DCP"
puts " BIT_FILE:  $BIT_FILE"
puts "======================================================="

# -------------------------------------------------------------------
# Step 1: Open synthesis checkpoint and inject new OOC wrapper
# -------------------------------------------------------------------
puts "Step 1/4: Opening post_synth.dcp ..."
open_checkpoint $POST_SYNTH

# Find wrapper cell in synthesis hierarchy
set wrapper_cells [get_cells -hierarchical -filter "REF_NAME == $WRAPPER_NAME"]
if {[llength $wrapper_cells] == 0} {
    set wrapper_cells [get_cells -hierarchical -filter "ORIG_REF_NAME == $WRAPPER_NAME"]
}
if {[llength $wrapper_cells] == 0} {
    puts "ERROR: Cell $WRAPPER_NAME not found. Dumping hierarchy..."
    get_cells -hierarchical -filter "REF_NAME =~ *rw_dm*" 
    exit 1
}
set wrapper_cell [lindex $wrapper_cells 0]
puts "Found synthesis wrapper cell: $wrapper_cell (REF_NAME=$WRAPPER_NAME)"

# Convert to black box (removes internal netlist, keeps module ports)
# At synthesis level, black-box = RTL module ports only (13 ports)
puts "Converting $wrapper_cell to black-box ..."
update_design -black_box -cells $wrapper_cell

# Inject new OOC synthesized wrapper (with hready_in_r)
puts "Reading new OOC DCP into wrapper cell ..."
read_checkpoint -cell $wrapper_cell $OOC_DCP

# Save the modified synthesis checkpoint
puts "Writing updated synthesis checkpoint: $ECO_SYNTH"
write_checkpoint -force $ECO_SYNTH
close_project
puts "Step 1/4 done."

# -------------------------------------------------------------------
# Step 2: Optimize (from modified synthesis checkpoint)
# -------------------------------------------------------------------
puts "Step 2/4: opt_design from ECO synth checkpoint ..."
open_checkpoint $ECO_SYNTH
opt_design -directive Explore
write_checkpoint -force $ECO_OPT
puts "Step 2/4 done."

# -------------------------------------------------------------------
# Step 3: Place + Route
# -------------------------------------------------------------------
puts "Step 3/4: place_design + route_design ..."
place_design -directive AltSpreadLogic_low
phys_opt_design -directive AggressiveExplore
write_checkpoint -force $ECO_PLACE
route_design -directive AggressiveExplore -tns_cleanup
write_checkpoint -force $ECO_ROUTE
puts "Step 3/4 done."

# -------------------------------------------------------------------
# Step 4: Bitstream — suppress the known CEVA IP combinatorial loop
# -------------------------------------------------------------------
puts "Step 4/4: Writing bitstream ..."

# Suppress CEVA IP internal AHB comb loop (known, existing issue)
set comb_net {chiptop0/system/pbus/ceva/ceva/u_rw_dm_top_tglp_ext/u_rw_dm_top/u_rw_dm_ahb_if/u_rw_dm_ahb_if_ahb2reg/hready_reg_0}
set found_nets [get_nets -quiet $comb_net]
if {[llength $found_nets] > 0} {
    set_property ALLOW_COMBINATORIAL_LOOPS TRUE $found_nets
    puts "Suppressed known CEVA IP comb loop: $comb_net"
} else {
    # Wildcard fallback
    set found [get_nets -quiet -hierarchical -filter {NAME =~ *hready_reg_0*}]
    if {[llength $found] > 0} {
        set_property ALLOW_COMBINATORIAL_LOOPS TRUE $found
        puts "Suppressed via wildcard: $found"
    }
}
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]

write_bitstream -force -file $BIT_FILE
puts "======================================================="
puts " ECO COMPLETE: $BIT_FILE"
puts "======================================================="
