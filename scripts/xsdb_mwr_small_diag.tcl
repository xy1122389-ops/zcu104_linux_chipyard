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

if {$tcl_platform(platform) eq "windows"} {
  set testfile {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\scripts\mwr_small_test.bin}
} else {
  set testfile /root/chipyard/fpga/scripts/mwr_small_test.bin
}

set base 0x01100000

step "connect" {
  connect -url tcp:127.0.0.1:3121
  configparams force-mem-accesses 1
}

step "select PSU" {
  targets -set -nocase -filter {name =~ "*PSU*"}
}

step "seed and write" {
  mwr -force $base 0xDEADBEEF
  mwr -force [expr {$base + 4}] 0xFEEDFACE
  mwr -force -bin -file $testfile $base 2
}

step "read back" {
  set v0 [mrd -force -value $base]
  set v1 [mrd -force -value [expr {$base + 4}]]
  puts [format "v0=0x%08x v1=0x%08x" $v0 $v1]
  puts "expected no-skip: v0=0xA5A5A5A5 v1=0x5A5A5A5A"
}

step "disconnect" {
  disconnect
}
exit
