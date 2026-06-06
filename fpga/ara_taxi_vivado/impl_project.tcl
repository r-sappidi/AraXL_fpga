if {$argc < 1} {
    puts "Usage: impl_project.tcl <project.xpr> \[to_step\] \[strategy\]"
    exit 1
}

set xpr [lindex $argv 0]
set to_step  [expr {$argc >= 2 ? [lindex $argv 1] : "write_bitstream"}]
set strategy [expr {$argc >= 3 ? [lindex $argv 2] : ""}]
# Alias for the post-route physical-opt step, whose real launch_runs name has a
# space + parens that don't survive make/shell tclargs quoting.
if {$to_step eq "postroute_physopt"} {
    set to_step {phys_opt_design (Post-Route)}
}
open_project $xpr

# Re-synthesize only if sources changed since the last synth (NEEDS_REFRESH);
# otherwise reuse the up-to-date netlist (saves a redundant ~15 min synth).
if {[get_property STATUS [get_runs synth_1]] eq "synth_design Complete!" &&
    [get_property NEEDS_REFRESH [get_runs synth_1]] == 0} {
    puts "SYNTH_STATUS=synth_design Complete! (reused, sources unchanged)"
} else {
    reset_run synth_1
    launch_runs synth_1 -jobs 8
    wait_on_run synth_1
    set synth_status [get_property STATUS [get_runs synth_1]]
    puts "SYNTH_STATUS=$synth_status"
    if {$synth_status ne "synth_design Complete!"} {
        puts "ERROR: synthesis did not complete"
        exit 1
    }
}

reset_run impl_1
# Register the LiteFury PCIe GT lane-LOC + pin hook as a pre-place script on the
# impl run. REQUIRED for PCIe to link-train: it places the XDMA GTs on the
# LiteFury's transceiver channels and assigns the pci_exp_* package pins (which
# exist in no .xdc -- only in this hook). Without it the GTs default to the wrong
# channels/pins and the link never reaches L0. create_project.tcl was meant to
# set this but the property did not persist, so set it here explicitly.
set gt_hook [file join [file dirname [file normalize [info script]]] apply_litefury_gt_locs.tcl]
if {[file exists $gt_hook]} {
    set_property STEPS.PLACE_DESIGN.TCL.PRE $gt_hook [get_runs impl_1]
    puts "REGISTERED_GT_HOOK=$gt_hook"
} else {
    puts "ERROR: GT LOC hook not found at $gt_hook -- PCIe lanes will be misplaced"
    exit 1
}
# Optional timing-driven strategy (e.g. Performance_ExplorePostRoutePhysOpt) to
# close the razor-thin 125 MHz XDMA-domain margin with Explore place/route +
# post-route physical optimization.
if {$strategy ne ""} {
    set_property strategy $strategy [get_runs impl_1]
    puts "IMPL_STRATEGY=$strategy"
}
launch_runs impl_1 -to_step $to_step -jobs 8
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]
puts "IMPL_STATUS=$impl_status"
puts "IMPL_PROGRESS=$impl_progress"

# Pull post-route timing if routing completed.
set proj_dir [get_property DIRECTORY [current_project]]
set timing_met 1
if {[file exists [get_property DIRECTORY [get_runs impl_1]]/[get_property top [current_fileset]]_routed.dcp]} {
    open_run impl_1
    set wns [get_property SLACK [get_timing_paths -setup -max_paths 1 -nworst 1]]
    set whs [get_property SLACK [get_timing_paths -hold  -max_paths 1 -nworst 1]]
    set timing_met [expr {$wns >= 0 && $whs >= 0}]
    puts "POST_ROUTE_WNS=$wns"
    puts "POST_ROUTE_WHS=$whs"
    puts "TIMING_MET=$timing_met"
    report_timing_summary -file [file join $proj_dir post_route_timing_summary.rpt]
    report_utilization     -file [file join $proj_dir post_route_utilization.rpt]
    report_drc             -file [file join $proj_dir post_route_drc.rpt]
}

if {$impl_progress ne "100%"} {
    puts "ERROR: implementation did not reach 100% (status: $impl_status)"
    exit 1
}
if {!$timing_met} {
    puts "IMPL_DONE_TIMING_FAILED"
    exit 1
}
puts "IMPL_OK"
exit
