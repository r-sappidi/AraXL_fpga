set script_dir [file normalize [file dirname [info script]]]
set fpga_dir [file normalize [file join $script_dir ../..]]
set xpr [file normalize [file join $fpga_dir build ara_taxi ara_taxi.xpr]]
set out_dir [file normalize [file join $fpga_dir build xdma_example]]

if {![file exists $xpr]} {
    puts stderr "Missing Vivado project: $xpr"
    puts stderr "Run: make -C $fpga_dir litefury-xpr NR_LANES=4 NR_CLUSTERS=2"
    exit 1
}

file delete -force $out_dir
file mkdir $out_dir

open_project $xpr
set ip [get_ips xdma_1]

set rc [catch {
    open_example_project -force -dir $out_dir $ip
} msg]

if {$rc != 0} {
    puts stderr "open_example_project failed: $msg"
    puts stderr "Trying generate_target example_design instead."
    set rc2 [catch {
        generate_target example_design [get_files -of_objects [get_filesets sources_1] */xdma_1.xci]
    } msg2]
    if {$rc2 != 0} {
        puts stderr "generate_target example_design failed: $msg2"
        exit 1
    }
}

puts "XDMA example project/output written under: $out_dir"
exit
