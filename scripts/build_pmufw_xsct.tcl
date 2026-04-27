# build_pmufw_xsct.tcl
# Run with: xsct build_pmufw_xsct.tcl
# Builds ZynqMP PMUFW from XSA and outputs pmufw.elf to C:\tmp\pmufw_build\

set xsa_path {C:/tmp/pmufw_build/zcu104.xsa}
set ws_path  {C:/tmp/pmufw_build/pmufw_ws}
set out_elf  {C:/tmp/pmufw_build/pmufw.elf}

puts "\[build_pmufw\] Setting workspace: $ws_path"
setws $ws_path

puts "\[build_pmufw\] Creating platform from: $xsa_path"
platform create -name zcu104 -hw $xsa_path
platform write
platform active zcu104

puts "\[build_pmufw\] Creating PMUFW application..."
app create -name pmufw_app -template "ZynqMP PMUFW" -hw $xsa_path -proc psu_pmu_0 -lang C

puts "\[build_pmufw\] Building PMUFW..."
app build pmufw_app

# Copy output elf
set built_elf "$ws_path/pmufw_app/Debug/pmufw_app.elf"
if {[file exists $built_elf]} {
    file copy -force $built_elf $out_elf
    puts "\[build_pmufw\] SUCCESS: pmufw.elf -> $out_elf"
} else {
    puts "\[build_pmufw\] WARNING: built elf not at expected path, searching..."
    set found [glob -nocomplain "$ws_path/pmufw_app/*/pmufw_app.elf"]
    if {[llength $found] > 0} {
        file copy -force [lindex $found 0] $out_elf
        puts "\[build_pmufw\] SUCCESS (alt path): [lindex $found 0] -> $out_elf"
    } else {
        puts "\[build_pmufw\] ERROR: pmufw.elf not found in workspace"
        exit 1
    }
}
puts "\[build_pmufw\] DONE"
exit
