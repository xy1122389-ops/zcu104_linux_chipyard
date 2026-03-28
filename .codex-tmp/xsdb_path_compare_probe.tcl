proc rd {addr} {
  catch {mrd -force $addr} rv
  puts [format "mrd 0x%08X => %s" $addr $rv]
}

proc probe_target {name} {
  puts ""
  puts "===== $name ====="
  targets -set -nocase -filter [format {name == "%s"} $name]
  catch {puts [targets]} err
  if {$err ne ""} { puts $err }
  rd 0x00000040
  rd 0x00000044
  rd 0x0000004C
  rd 0x00000100
  rd 0x00010000
  rd 0x00010004
  rd 0x00100000
  rd 0x00110000
  rd 0x02000000
}

connect -url tcp:127.0.0.1:3121
configparams force-mem-accesses 1
probe_target "PSU"
probe_target "APU (L2 Cache Reset)"
disconnect
exit
