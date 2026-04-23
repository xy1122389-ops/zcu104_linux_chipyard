set confirm off
set pagination off
set architecture riscv:rv64
set remotetimeout 30

define dump_state
  echo --- state ---\n
  info reg pc
  monitor ReadCSR 0x342
  monitor ReadCSR 0x305
  monitor ReadCSR 0x341
end

target remote :3333
monitor halt
echo === initial ===\n
dump_state

echo === read VERSION first time ===\n
x/1wx 0x601700FC
dump_state

echo === read VERSION second time ===\n
x/1wx 0x601700FC
dump_state

echo === read CAPS_LO ===\n
x/1wx 0x60170040
dump_state

echo === read PRESENT_STATE ===\n
x/1wx 0x60170024
dump_state

detach
quit
