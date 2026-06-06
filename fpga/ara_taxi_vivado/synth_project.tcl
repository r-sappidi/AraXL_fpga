if {$argc < 1} {
    puts "Usage: synth_project.tcl <project.xpr>"
    exit 1
}

set xpr [lindex $argv 0]
open_project $xpr
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_STATUS=$synth_status"
if {$synth_status ne "synth_design Complete!"} {
    exit 1
}
open_run synth_1 -name synth_1
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir apply_litefury_gt_locs.tcl]
set proj_dir [get_property DIRECTORY [current_project]]
report_utilization -file [file join $proj_dir post_synth_utilization.rpt]
report_utilization -hierarchical -file [file join $proj_dir post_synth_utilization_hier.rpt]
exit
