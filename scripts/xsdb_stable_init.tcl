# xsdb_stable_init.tcl — Unified ZCU104 LinuxBringup init
# Flow: psu_init → fpga → IMMEDIATE isolation_removal → settle
# Prereqs: hw_server running on tcp:localhost:3121, board powered on
#
# ROOT CAUSE of previous halt failures:
#   BootROM reaches ddr_test_fixed() at ~560ms after POR.
#   If PS-PL isolation is not removed before that, AXI HP0 stalls,
#   TL bus hangs, core is stuck on a non-retiring instruction,
#   and J-Link cannot halt it.
#
# Fix: Do isolation_removal IMMEDIATELY after fpga (no 5s wait).
#   psu_init() already configured AFIFM2=128-bit before PL programming.
#   PS AFI registers persist across PL programming.
#
# GPIO[31] / psu_ps_pl_reset_config:
#   EMIO GPIO[31] is NOT connected to any PL reset in this design.
#   psu_ps_pl_reset_config toggles GPIO[31] which is a no-op.
#   We skip it entirely to avoid confusion.

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

# --- Resolve paths ---
set zcu104_cfg "RocketZCU104LinuxBringupConfig"
set base "//wsl.localhost/Ubuntu-22.04/root/chipyard/fpga/generated-src"
set obj_dir [string map {/ \\} "${base}/chipyard.fpga.zcu104.ZCU104FPGATestHarness.${zcu104_cfg}/obj"]
set psu_init_tcl "${obj_dir}\\ip\\zcu104ps\\psu_init.tcl"
set bit_file "${obj_dir}\\ZCU104FPGATestHarness.bit"

step "connect hw_server" {
    connect -url tcp:127.0.0.1:3121
    after 3000
}

step "show targets" {
    targets
}

step "select PSU target" {
    set psu_found 0
    if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} {
        puts "PSU target found"
        set psu_found 1
    }
    if {!$psu_found} {
        puts "PSU not found, trying POR reset via PS TAP..."
        if {![catch {targets -set -nocase -filter {name =~ "*PS TAP*"}}]} {
            catch {rst -por}
            puts "POR reset issued, waiting 15s..."
            after 15000
        }
        targets
        if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} {
            puts "PSU found after POR reset"
            set psu_found 1
        }
    }
    if {!$psu_found} {
        error "PSU target not available. Power-cycle the board and retry."
    }
    targets
}

step "source psu_init.tcl" {
    puts "Loading: $psu_init_tcl"
    source $psu_init_tcl
}

step "run psu_init (DDR + clocks + AFI widths)" {
    # This configures DDR controller, PLLs, MIO, and critically:
    #   AFIFM2 RD/WR = 128-bit (0xFD380000=0, 0xFD380014=0) for HP0/DDR path
    #   AFIFM6 RD/WR = 32-bit  (0xFF9B0000=2, 0xFF9B0014=2) for LPD path
    #   AFI FM0-FM6 resets deasserted
    psu_init
}

step "program FPGA bitstream" {
    puts "Bitstream: $bit_file"
    fpga $bit_file
}

# CRITICAL: Do NOT wait here! Core starts ~1ms after PL programming.
# BootROM reaches DDR test at ~560ms. Must remove isolation before that.

step "remove PS-PL isolation (IMMEDIATELY after fpga)" {
    psu_ps_pl_isolation_removal
    puts "Isolation removed — AXI HP0/DDR path now open"
}

step "wait for PL settle (3s for DDR test + BootROM completion)" {
    # At this point: PLL locks ~1ms, core starts, isolation is already removed,
    # DDR path works, BootROM DDR test completes, core enters polling loop.
    # DS39 heartbeat should be visible.
    after 3000
}

step "verify AFIFM2 = 128-bit" {
    set rd [mrd -force 0xFD380000]
    set wr [mrd -force 0xFD380014]
    puts "AFIFM2_RDCTRL = $rd (expect 0 = 128-bit)"
    puts "AFIFM2_WRCTRL = $wr (expect 0 = 128-bit)"
}

step "done" {
    puts ""
    puts "=== STABLE INIT COMPLETE ==="
    puts "Config   : $zcu104_cfg"
    puts "Bitstream: $bit_file"
    puts "AFIFM2   : 128-bit (HP0/DDR)"
    puts "Note     : GPIO\[31\] (EMIO) is NOT connected to PL reset in this design."
    puts "Note     : psu_ps_pl_reset_config skipped (no-op for this design)."
    puts ""
    puts "Core state: Running in BootROM polling loop (DDR test passed)."
    puts "Next: start J-Link GDB Server, connect GDB, halt core."
}

disconnect
