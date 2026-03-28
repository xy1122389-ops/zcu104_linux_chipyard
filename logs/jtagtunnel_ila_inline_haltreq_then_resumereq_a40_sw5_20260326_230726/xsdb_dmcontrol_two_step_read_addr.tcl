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
$seq drshift -capture -integer 53 0x420000000653
puts "WRITE1_haltreq_then_resumereq=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x53
puts "NOP1_haltreq_then_resumereq=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x410000000653
puts "WRITE2_haltreq_then_resumereq=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x53
puts "NOP2_haltreq_then_resumereq=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x1000000000153
puts "READ_0x40_haltreq_then_resumereq=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x53
puts "NOPR1_0x40_haltreq_then_resumereq=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
$seq drshift -capture -integer 53 0x53
puts "NOPR2_0x40_haltreq_then_resumereq=[$seq run -hex]"
exit
