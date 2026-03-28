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

proc select_psu_target {} {
  if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} {
    return
  }
  error "unable to select PSU target"
}

set gpio_base       0x64002000
set gpio_output_en  [expr {$gpio_base + 0x08}]
set gpio_output_val [expr {$gpio_base + 0x0C}]
set gpio_iof_en     [expr {$gpio_base + 0x38}]

step "connect hw_server" {
  connect -url tcp:127.0.0.1:3121
}

step "select PSU" {
  select_psu_target
}

step "sample gpio registers" {
  for {set i 0} {$i < 20} {incr i} {
    puts "SAMPLE_$i OUTPUT_EN=[mrd $gpio_output_en]"
    puts "SAMPLE_$i OUTPUT_VAL=[mrd $gpio_output_val]"
    puts "SAMPLE_$i IOF_EN=[mrd $gpio_iof_en]"
    after 200
  }
}

step "disconnect" {
  disconnect
}

exit
