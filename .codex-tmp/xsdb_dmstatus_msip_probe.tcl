proc show_targets {tag} {
  puts ""
  puts "===== $tag : targets ====="
  catch {puts [targets]} err
  if {$err ne ""} { puts $err }
}

proc rd {addr} {
  catch {mrd -force $addr} rv
  puts [format "mrd 0x%08X => %s" $addr $rv]
}

connect -url tcp:127.0.0.1:3121
targets -set -nocase -filter {name =~ "*PSU*"}
show_targets "initial"

puts ""
puts "===== baseline ====="
rd 0x00000044
rd 0x0000004C
rd 0x00000100
rd 0x000000E0
rd 0x00010000
rd 0x00010004
rd 0x00010008
rd 0x0001000C
rd 0x00100000
rd 0x00110000
rd 0x02000000

puts ""
puts "===== clear msip ====="
catch {mwr 0x02000000 0x0} clear_rv
puts "mwr 0x02000000 0x0 => $clear_rv"
rd 0x02000000
rd 0x00000044
rd 0x0000004C
rd 0x00000100

puts ""
puts "===== assert msip ====="
catch {mwr 0x02000000 0x1} set_rv
puts "mwr 0x02000000 0x1 => $set_rv"

for {set i 0} {$i < 20} {incr i} {
  puts [format "-- poll %d --" $i]
  rd 0x02000000
  rd 0x00000044
  rd 0x0000004C
  rd 0x00000100
  after 100
}

show_targets "final"
disconnect
exit
