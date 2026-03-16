if {$argc < 4 || $argc > 5} {
  puts {Error: Invalid number of arguments}
  puts {Usage: write_cfgmem_generic.tcl iface size mcsfile bitfile [datafile]}
  exit 1
}

lassign $argv iface size mcsfile bitfile datafile

set load_data_arg [expr {$datafile ne "" ? "-loaddata up 0x400000 $datafile" : ""}]

set cmd [list write_cfgmem -format mcs -interface $iface -size $size -loadbit "up 0x0 $bitfile" -file $mcsfile -force]
if {$datafile ne ""} {
  lappend cmd -loaddata "up 0x400000 $datafile"
}

puts "Running: $cmd"
eval $cmd
