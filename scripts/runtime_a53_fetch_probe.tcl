proc section {label} {
  puts ""
  puts "==== $label ===="
  flush stdout
}

proc select_a53_0 {} {
  if {![catch {targets 9}]} { return }
  if {![catch {targets -set -nocase -filter {name =~ "*Cortex-A53 #0*"}}]} { return }
  error "unable to select Cortex-A53 #0"
}

proc try_cmd {label body} {
  section $label
  if {[catch {uplevel 1 $body} out opts]} {
    puts "CMD_OK=NO"
    puts "CMD_VALUE=[string trim $out]"
    if {[dict exists $opts -errorinfo]} {
      puts [dict get $opts -errorinfo]
    }
  } else {
    puts "CMD_OK=YES"
    puts [string trim $out]
  }
  flush stdout
}

connect -url tcp:127.0.0.1:3121
select_a53_0
catch {stop}
after 100

section "target"
puts [targets]
puts "PC=[string trim [rrd pc]]"
puts "CPSR=[string trim [rrd cpsr]]"

try_cmd "help dis" {help dis}
try_cmd "help disassemble" {help disassemble}
try_cmd "dis raw positional" {dis 0x1f0 16}
try_cmd "dis raw flags" {dis -addr 0x1f0 -count 16}
try_cmd "disassemble positional" {disassemble 0x1f0 16}
try_cmd "disassemble flags" {disassemble -address 0x1f0 -count 16}
try_cmd "a53 target props" {targets -target-properties -filter {name =~ "*Cortex-A53 #0*"}}

catch {disconnect}
exit
