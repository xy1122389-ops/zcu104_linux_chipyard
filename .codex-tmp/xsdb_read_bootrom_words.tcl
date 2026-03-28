proc rd {addr} {
  catch {mrd -force $addr} rv
  puts [format "mrd %s => %s" $addr $rv]
}

connect -url tcp:127.0.0.1:3121
targets -set -nocase -filter {name =~ "*PSU*"}
catch {configparams force-mem-accesses 1} fm
puts "configparams force-mem-accesses 1 => $fm"
rd 0x00010000
rd 0x00010004
rd 0x00010008
rd 0x0001000C
rd 0x00010080
rd 0x00010084
disconnect
exit
