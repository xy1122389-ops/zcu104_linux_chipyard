set pagination off
set confirm off
target extended-remote 172.19.128.1:2331

file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

# === Restart from OpenSBI ===
echo \n=== Restarting from OpenSBI (memory intact) ===\n

# Reset CPU state
set $pc = 0x80000000
set $a0 = 0

# Set breakpoints
# 1. OpenSBI mret → kernel entry
hbreak *0x8000b2b2
echo [bp] mret at 0x8000b2b2\n
continue

# Hit mret
echo \n=== OpenSBI mret reached ===\n
printf "mepc = 0x%lx\n", $mepc
printf "a0 = 0x%lx (hartid)\n", $a0
printf "a1 = 0x%lx (dtb addr)\n", $a1
delete 1

# Set breakpoint at platform_bus_init (called once)
hbreak platform_bus_init
echo [bp] platform_bus_init set\n
continue

echo \n=== platform_bus_init reached ===\n
printf "pc = 0x%lx\n", $pc
printf "ra = 0x%lx\n", $ra

# Now set breakpoint at bus_register (called from platform_bus_init)
hbreak bus_register
delete 2
continue

echo \n=== bus_register reached ===\n
printf "a0 = 0x%lx (bus_type ptr)\n", $a0
# Inspect bus_type structure (name is first field for struct bus_type)
echo [bus_type] Memory dump:\n
x/8xg $a0
# Print the name pointer (first field should be const char *name)
echo [bus_type.name] String at first ptr:\n
x/1s *(char **)$a0

# Set breakpoint at kset_register
hbreak kset_register
delete 3
continue

echo \n=== kset_register reached ===\n
printf "a0 = 0x%lx (kset ptr)\n", $a0
echo [kset] Memory dump:\n
x/16xg $a0

# Now let it run and catch the crash
# Set breakpoint at the faulting strlen instruction
hbreak *0xffffffff80451c54
delete 4
echo \n=== Continuing to strlen crash... ===\n
continue

echo \n=== strlen hit (may be pre-crash or normal call) ===\n
printf "a0 = 0x%lx (string ptr for strlen)\n", $a0
echo [string] Attempting to read:\n
x/1s $a0
echo [memory] Raw bytes at a0:\n
x/16bx $a0

quit
