connect -url tcp:127.0.0.1:3121
jtag targets -set -filter {name == "xczu7"}
jtag frequency 10000
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 16 0x100a
puts "SEL=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 44 0x41
puts "DTMCS=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x400000000653
puts "WRITE_dmactive=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x53
puts "NOP1_dmactive=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x53
puts "NOP2_dmactive=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x440000000153
puts "READ_DMSTATUS_dmactive=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x53
puts "NOPR1_dmactive=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x53
puts "NOPR2_dmactive=[$seq run -hex]"
exit
