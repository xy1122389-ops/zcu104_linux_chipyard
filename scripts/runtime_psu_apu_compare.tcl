proc try_select_psu {} {
  if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} { return }
  error "unable to select PSU"
}

proc try_select_apu {} {
  if {![catch {targets -set -nocase -filter {name == "APU (L2 Cache Reset)"}}]} { return }
  if {![catch {targets -set -nocase -filter {name == "APU"}}]} { return }
  if {![catch {targets 8}]} { return }
  error "unable to select APU"
}

proc dump_for {prefix} {
  foreach addr {0x0 0x200 0x1000 0x1e0 0x2000 0x2200} {
    if {[catch {mrd $addr 2} out]} {
      puts [format "%s_%s=ERR:%s" $prefix [string toupper $addr] [string trim $out]]
    } else {
      puts [format "%s_%s=%s" $prefix [string toupper $addr] [string trim $out]]
    }
  }
  flush stdout
}

connect -url tcp:127.0.0.1:3121
configparams force-mem-accesses 1
try_select_psu
dump_for PSU
try_select_apu
dump_for APU
catch {disconnect}
exit
