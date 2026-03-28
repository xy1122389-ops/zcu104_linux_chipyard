connect -url tcp:127.0.0.1:3121
jtag targets -set -filter {name == "xczu7"}
jtag frequency 10000
set seq [jtag sequence]
$seq irshift -integer 12 0x926
\\$seq drshift -capture -integer 16 0x100a
puts "SEL=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
\\$seq drshift -capture -integer 44 0x41
puts "DTMCS=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
\\$seq drshift -capture -integer 53 0x653
puts "WRITE_HALTREQ=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
\\$seq drshift -capture -integer 53 0x53
puts "PRENOP1=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
\\$seq drshift -capture -integer 53 0x53
puts "PRENOP2=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
\\$seq drshift -capture -integer 53 0x153
puts "READ_0x11=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
\\$seq drshift -capture -integer 53 0x53
puts "POSTNOP1=[$seq run -hex]"
set seq [jtag sequence]
$seq irshift -integer 12 0x926
\\$seq drshift -capture -integer 53 0x53
puts "POSTNOP2=[$seq run -hex]"
exit
