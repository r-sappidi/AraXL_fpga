set script_dir [file normalize [file dirname [info script]]]
set fpga_dir   [file normalize [file join $script_dir ../..]]
set main_xpr   [file normalize [file join $fpga_dir build ara_taxi ara_taxi.xpr]]

if {$argc != 2} {
    puts stderr "Usage: run_araxl_dotproduct_xsim.tcl <payload.hex> <payload_len>"
    exit 1
}
set payload_hex [file normalize [lindex $argv 0]]
set payload_len [lindex $argv 1]

if {![file exists $main_xpr]} {
    puts stderr "Missing prepared project: $main_xpr"
    puts stderr "Run: make -C $fpga_dir araxl-xdma-xsim-setup"
    exit 1
}

open_project $main_xpr
set simset [get_filesets sim_1]
set_property top board $simset
# Diagnostic/stub defines must NOT persist across runs. set_property below
# bakes whatever we pass into the project's verilog_define, so one-off runs
# leave them stuck on for every later run. Strip them here; they are re-added
# below only when ARAXL_EXTRA_DEFINES explicitly asks for them.
set defs [get_property verilog_define $simset]
foreach stale_define {ARAXL_AXI_PROBE XSIM_XDMA_AXI_STUB} {
    set did_strip 0
    while {[set pidx [lsearch -exact $defs $stale_define]] >= 0} {
        set defs [lreplace $defs $pidx $pidx]
        set did_strip 1
    }
    if {$did_strip} {
        puts "AraXL xsim: stripped stale $stale_define from project defines"
    }
}
set_property verilog_define $defs $simset
# Optional diagnostic defines (toggle via env without re-running prepare).
if {[info exists env(ARAXL_EXTRA_DEFINES)] && $env(ARAXL_EXTRA_DEFINES) ne ""} {
    set defs [get_property verilog_define $simset]
    foreach d $env(ARAXL_EXTRA_DEFINES) {
        if {[lsearch -exact $defs $d] < 0} { lappend defs $d }
    }
    set_property verilog_define $defs $simset
    puts "AraXL xsim extra defines: $env(ARAXL_EXTRA_DEFINES)"
}
# Keep xelab options clean (a one-off --O0 experiment was tried and reverted;
# strip it in case it got baked into the persisted project property).
set xo [get_property xsim.elaborate.xelab.more_options $simset]
set_property xsim.elaborate.xelab.more_options [string trim [string map {--O0 {}} $xo]] $simset
set_property xsim.simulate.runtime all $simset
# Batch run only needs to reach the exit register / link-up milestone, not
# produce waveforms. Logging the full hierarchy under "run all" makes xsim
# buffer every signal for the whole run, exhausting RAM+swap (OOM). Disable
# debug/wave logging unless ARAXL_XSIM_WAVES=1.
if {![info exists env(ARAXL_XSIM_WAVES)] || $env(ARAXL_XSIM_WAVES) eq "0"} {
    set_property xsim.elaborate.debug_level off $simset
    set_property xsim.simulate.log_all_signals false $simset
} else {
    # Wave-capture mode (ARAXL_XSIM_WAVES=1). The full-hierarchy OOM only bit the
    # un-stubbed AraXL fabric; the XSIM_XDMA_AXI_STUB boundary design is small, so
    # we can log signals. A narrow custom-tcl (set via ARAXL_XSIM_WAVE_TCL) keeps
    # it minimal; otherwise fall back to logging all signals (cap-protected).
    set_property xsim.elaborate.debug_level all $simset
    if {[info exists env(ARAXL_XSIM_WAVE_TCL)] && [file exists $env(ARAXL_XSIM_WAVE_TCL)]} {
        set_property xsim.simulate.log_all_signals false $simset
        set_property xsim.simulate.custom_tcl $env(ARAXL_XSIM_WAVE_TCL) $simset
        puts "AraXL xsim: narrow wave capture via $env(ARAXL_XSIM_WAVE_TCL)"
    } else {
        set_property xsim.simulate.log_all_signals true $simset
        puts "AraXL xsim: full-signal wave capture (cap-protected)"
    }
}
set_property xsim.simulate.xsim.more_options " -testplusarg TESTNAME=araxl_dotproduct -testplusarg ARAXL_PAYLOAD_HEX=$payload_hex -testplusarg ARAXL_PAYLOAD_LEN=$payload_len" $simset

if {[catch {launch_simulation -simset sim_1 -mode behavioral} sim_error]} {
    puts stderr "AraXL XDMA xsim failed during launch_simulation: $sim_error"
    exit 1
}

set sim_log [file join [file dirname $main_xpr] ara_taxi.sim sim_1 behav xsim simulate.log]
if {![file exists $sim_log]} {
    puts stderr "AraXL XDMA xsim failed: missing simulation log: $sim_log"
    exit 1
}
set fh [open $sim_log r]
set sim_data [read $fh]
close $fh

set fail_patterns [list \
    {ERROR: PCIe link-up timeout} \
    {Fatal: PCIe link did not train} \
    {PCIe link did not train} \
    {Simulator command interrupted} \
    {terminated in an unexpected manner} \
    {Unrecognized TESTNAME} \
    {---\*\*\*ERROR\*\*\*} \
    {Data MISMATCH} \
]
foreach pattern $fail_patterns {
    if {[regexp -- $pattern $sim_data]} {
        puts stderr "AraXL XDMA xsim failed: matched failure pattern: $pattern"
        exit 1
    }
}

# STEP 3 milestone: the GTPE2<->GTPE2 link must train. STEP 4 will restore the
# stronger "Ara exit register written" gate once the payload stimulus lands.
if {[regexp {XDMA-STUB PASS} $sim_data]} {
    puts "AraXL XDMA boundary xsim PASSED: real XDMA reached AraXL AXI boundary."
    exit
}
if {[regexp {Ara exit register written} $sim_data]} {
    puts "AraXL XDMA xsim PASSED: Ara exit register written."
    exit
}
if {[regexp {PCIe link is up} $sim_data]} {
    puts "AraXL XDMA xsim link-up milestone PASSED (EP user_lnk_up=1)."
    exit
}
puts stderr "AraXL XDMA xsim failed: link did not come up and exit register not written"
exit 1
