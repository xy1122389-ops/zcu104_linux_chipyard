proc try_select_a53_0 {} {
  if {![catch {targets 9}]} { return }
  if {![catch {targets -set -nocase -filter {name =~ "*Cortex-A53 #0*"}}]} { return }
  error "unable to select Cortex-A53 #0"
}

proc rd {name} {
  if {[catch {rrd $name} out]} {
    puts "REG_$name=ERR:[string trim $out]"
  } else {
    puts "REG_$name=[string trim $out]"
  }
  flush stdout
}

set regs {
  pc cpsr r0 r14 r30 sp
  currentel
  spsr_el3 elr_el3 esr_el3 far_el3 vbar_el3 scr_el3 sctlr_el3 ttbr0_el3 tcr_el3
  spsr_el1 elr_el1 esr_el1 far_el1 vbar_el1 sctlr_el1 ttbr0_el1 tcr_el1
  mpidr_el1 midr_el1
  dbgdscr mdscr_el1
}

connect -url tcp:127.0.0.1:3121
try_select_a53_0
catch {stop}
after 100
puts "TARGET=[targets]"
foreach reg $regs {
  rd $reg
}
catch {disconnect}
exit
