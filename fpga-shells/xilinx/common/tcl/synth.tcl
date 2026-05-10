# See LICENSE for license details.

# Read the specified list of IP files
read_ip [glob -directory $ipdir [file join * {*.xci}]]

# Force single-threaded synthesis: Vivado 2021.2 multithreaded synth_design
# deadlocks on Berkeley HardFloat + SiFive L2 SRAM patterns.
set_param synth.maxThreads 1
set_param general.maxThreads 1

# Synthesize the design
synth_design -top $top -flatten_hierarchy rebuilt

# Checkpoint the current design
write_checkpoint -force [file join $wrkdir post_synth]
