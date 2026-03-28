proc try_select_apu {} {
  if {![catch {targets -set -nocase -filter {name == "APU (L2 Cache Reset)"}}]} { return }
  if {![catch {targets -set -nocase -filter {name == "APU"}}]} { return }
  if {![catch {targets 8}]} { return }
  error "unable to select APU"
}

proc dump_addr {addr} {
  if {[catch {mrd $addr 2} out]} {
    puts [format "MRD_%s=ERR:%s" [string toupper $addr] [string trim $out]]
  } else {
    puts [format "MRD_%s=%s" [string toupper $addr] [string trim $out]]
  }
  flush stdout
}

connect -url tcp:127.0.0.1:3121
configparams force-mem-accesses 1
try_select_apu
dump_addr 0x0
dump_addr 0x200
dump_addr 0x2000
dump_addr 0x21e0
dump_addr 0x2200
dump_addr 0x4000
dump_addr 0x4200
dump_addr 0x80000000
dump_addr 0x80000200
dump_addr 0x80002000
dump_addr 0x80002200
catch {disconnect}
exit
