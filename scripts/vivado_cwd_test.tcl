puts "before cd pwd=[pwd]"
catch {cd /root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig} cdres
puts "cdres=$cdres"
puts "after cd pwd=[pwd]"
exit
