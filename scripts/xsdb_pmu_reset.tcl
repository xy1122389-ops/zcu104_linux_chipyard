# PMU POR reset to recover from DAP AXI error state
# After reset, wait for PS to re-boot, then reconnect

puts "==== Connect ===="
connect -url tcp:127.0.0.1:3121

puts "\n==== Targets before reset ===="
targets

puts "\n==== Select PMU ===="
targets -set -nocase -filter {name =~ "*PMU*"}

puts "\n==== POR Reset ===="
rst -por

puts "\n==== Wait 20s for PS re-boot ===="
after 20000

puts "\n==== Disconnect and reconnect ===="
disconnect
after 2000
connect -url tcp:127.0.0.1:3121

puts "\n==== Targets after reset ===="
targets

puts "\nDone. Check if PSU target is now available."
disconnect
exit
