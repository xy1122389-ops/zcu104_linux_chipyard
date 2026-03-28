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
$seq drshift -capture -integer 53 0x653
puts "WRITE_HALTREQ=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x53
puts "NOP1_HALTREQ=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x4001ce53
puts "WRITE_PROGBUF0=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x53
puts "NOP1_PROGBUF0=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x90400253
puts "WRITE_COMMAND=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x53
puts "NOP1_COMMAND=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x53
puts "NOP2_COMMAND=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x153
puts "READ_ABSTRACTCS=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x53
puts "NOP1_ABSTRACTCS=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x153
puts "READ_DATA0=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x53
puts "NOP1_DATA0=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x53
puts "NOP2_DATA0=[$seq run -hex]"
exit
