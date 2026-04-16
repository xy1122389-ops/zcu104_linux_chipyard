# POR reset then full init
connect -url tcp:127.0.0.1:3121
targets -set -nocase -filter {name =~ "PS TAP"}
puts "Issuing POR..."
rst -por
after 5000
puts "POR complete, checking targets..."
targets
disconnect
exit
