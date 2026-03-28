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
$seq drshift -capture -integer 53 0x480000000153
puts "REQ_0x12=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x53
puts "NOP1_0x12=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x53
puts "NOP2_0x12=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x53
puts "NOP3_0x12=[$seq run -hex]"
exit
