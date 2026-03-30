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
  set testfile {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\scripts\mwr_offset_test.bin}
} else {
  set testfile /root/chipyard/fpga/scripts/mwr_offset_test.bin
}

set base 0x01000000

step "connect" {
  connect -url tcp:127.0.0.1:3121
  configparams force-mem-accesses 1
}

step "select PSU target" {
  targets -set -nocase -filter {name =~ "*PSU*"}
}

step "seed memory with known pattern" {
  mwr -force $base 0xAAAAAAAA
  mwr -force [expr {$base + 0x1000}] 0xBBBBBBBB
  mwr -force [expr {$base + 0x2000}] 0xCCCCCCCC
}

step "mwr -bin -file write" {
  set fsize [file size $testfile]
  set words [expr {($fsize + 3) / 4}]
  puts "testfile=$testfile size=$fsize words=$words"
  mwr -force -bin -file $testfile $base $words
}

step "read back key addresses" {
  set v0 [mrd -force -value $base]
  set v1 [mrd -force -value [expr {$base + 0x4}]]
  set v1000 [mrd -force -value [expr {$base + 0x1000}]]
  set v2000 [mrd -force -value [expr {$base + 0x2000}]]
  set v2004 [mrd -force -value [expr {$base + 0x2004}]]
  puts [format "mem\[%08x\]      = 0x%08x" $base $v0]
  puts [format "mem\[%08x + 4\]  = 0x%08x" $base $v1]
  puts [format "mem\[%08x+1000\] = 0x%08x" $base $v1000]
  puts [format "mem\[%08x+2000\] = 0x%08x" $base $v2000]
  puts [format "mem\[%08x+2004\] = 0x%08x" $base $v2004]
  puts "Expected if NO offset: base=0x11111111, base+0x1000=0x22222222, base+0x2000=0x33333333"
  puts "Expected if +0x2000 source skip: base=0x33333333, base+4=0x44444444"
}

step "disconnect" {
  disconnect
}

exit
