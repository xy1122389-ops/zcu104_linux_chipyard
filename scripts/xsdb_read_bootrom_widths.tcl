proc try {label body} {
  puts ""
  puts "==== $label ===="
  if {[catch {uplevel 1 $body} err opts]} {
    puts "ERROR: $err"
    if {[dict exists $opts -errorinfo]} {
      puts [dict get $opts -errorinfo]
    }
  }
}

connect -url tcp:127.0.0.1:3121
targets -set -nocase -filter {name =~ "*PSU*"}
puts [targets]

try "mrd default 4 words @0x10000" {
  puts [mrd -force 0x00010000 4]
}

try "mrd byte 16 @0x10000" {
  puts [mrd -force -size b 0x00010000 16]
}

try "mrd halfword 8 @0x10000" {
  puts [mrd -force -size h 0x00010000 8]
}

try "mrd word 4 @0x10000" {
  puts [mrd -force -size w 0x00010000 4]
}

try "mrd dword 2 @0x10000" {
  puts [mrd -force -size d 0x00010000 2]
}

disconnect
exit
