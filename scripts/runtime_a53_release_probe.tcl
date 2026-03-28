proc emit {key value} {
  puts "$key=$value"
  flush stdout
}

proc rr {reg} {
  if {[catch {rrd $reg} out]} {
    return "ERR:[string trim $out]"
  }
  return [string trim $out]
}

proc mr {addr words} {
  if {[catch {mrd $addr $words} out]} {
    return "ERR:[string trim $out]"
  }
  return [string trim $out]
}

proc select_one {filter} {
  targets -set -nocase -filter $filter
}

proc pc_to_hex {pcraw} {
  if {[regexp -nocase {pc:\s*([0-9a-f]+)} $pcraw -> hx]} { return [string toupper $hx] }
  if {[regexp -nocase {0x([0-9a-f]+)} $pcraw -> hx2]} { return [string toupper $hx2] }
  return ""
}

connect -url tcp:127.0.0.1:3121
configparams force-mem-accesses 1

select_one {name =~ "*PSU*"}
emit "PRE_BOOTADDR_LO" [mr 0x1000 1]
emit "PRE_BOOTADDR_HI" [mr 0x1004 1]
emit "PRE_MSIP" [mr 0x2000000 1]
select_one {name =~ "*APU*"}
emit "PRE_MEM_01E0" [mr 0x1e0 2]
emit "PRE_MEM_0200" [mr 0x200 2]

select_one {name =~ "*Cortex-A53 #0*"}
emit "PRE_A53_PC" [rr pc]
emit "PRE_A53_CPSR" [rr cpsr]

catch {stop}
catch {bpremove -all}
catch {bpadd -type hw -addr 0x0000000000000200}
catch {rst -processor}
after 100
catch {con}
after 300
catch {stop}

set post_pc [rr pc]
set post_cpsr [rr cpsr]
set post_pc_hex [pc_to_hex $post_pc]
set hit0200 NO
if {$post_pc_hex eq "0000000000000200" || $post_pc_hex eq "200"} {
  set hit0200 YES
}

emit "POST_A53_PC" $post_pc
emit "POST_A53_CPSR" $post_cpsr
emit "POST_A53_HIT_0200" $hit0200
emit "POST_MEM_0200" [mr 0x200 2]

catch {bpremove -all}
catch {disconnect}
exit
