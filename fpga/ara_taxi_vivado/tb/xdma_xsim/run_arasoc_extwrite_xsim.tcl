# Standalone ara_soc ext-write isolation sim (no XDMA, no PIPE, no XSIM hacks).
# Uses a fresh simset (sim_2) so the XDMA board.v (which needs XSIM) is NOT
# compiled. Compiles ara_soc + design deps with the full define set MINUS XSIM
# (and minus the stale ARAXL_* diagnostic defines), so ara_soc runs with none
# of the ifdef-XSIM clock-gate / forced-mux hacks.

set script_dir [file normalize [file dirname [info script]]]
set fpga_dir   [file normalize [file join $script_dir ../..]]
set main_xpr   [file normalize [file join $fpga_dir build ara_taxi ara_taxi.xpr]]
if {![file exists $main_xpr]} {
    puts stderr "Missing prepared project: $main_xpr (run: make araxl-xdma-xsim-setup)"
    exit 1
}
open_project $main_xpr

set tbf [file normalize [file join $script_dir tb_arasoc_extwrite.sv]]

# Fresh simset so we don't drag in board.v / XDMA sim sources.
if {[lsearch -exact [get_filesets -quiet *] sim_2] < 0} {
    create_fileset -simset sim_2
}
set simset [get_filesets sim_2]

# Add the standalone TB + CVA6's sim-only instruction-tracer sources (these
# live in the original sim fileset, not the design fileset; cva6.sv instantiates
# them under `ifndef VERILATOR`, so a fresh simset must include them).
set extra_srcs [list \
    $tbf \
    [file normalize [file join $fpga_dir ../../hardware/deps/ariane/core/include/instr_tracer_pkg.sv]] \
    [file normalize [file join $fpga_dir ../../hardware/deps/ariane/common/local/util/instr_tracer_if.sv]] \
    [file normalize [file join $fpga_dir ../../hardware/deps/ariane/common/local/util/instr_tracer.sv]] \
]
foreach f $extra_srcs {
    if {[lsearch -exact [get_files -quiet -of_objects $simset] $f] < 0} {
        add_files -fileset $simset -norecurse $f
    }
}
set_property top tb_arasoc_extwrite $simset
set_property top_lib xil_defaultlib $simset

# Carry over include dirs from the design + original simset so the design's
# `include "axi/typedef.svh"` etc. resolve.
set inc {}
foreach fs {sources_1 sim_1} {
    foreach d [get_property include_dirs [get_filesets $fs]] { if {[lsearch -exact $inc $d] < 0} {lappend inc $d} }
    foreach d [get_property verilog_include_dirs [get_filesets $fs]] { if {[lsearch -exact $inc $d] < 0} {lappend inc $d} }
}
set_property include_dirs $inc $simset

# Defines: the full sim set MINUS XSIM (and the stale ARAXL_* diag defines), but
# KEEPING SIMULATION (behavioral models need it). Hardcoded so a freshly-created
# simset can't re-inherit XSIM at launch. This is Option E: ara_soc runs with NO
# ifdef-XSIM clock-gate / forced-mux hacks -> core is clocked while held in reset
# -> clean reset (no unclocked-X).
set clean {
    TARGET_CV64A6_IMAFDCV_SV39 TARGET_FPGA TARGET_RTL TARGET_SYNTHESIS
    TARGET_TECH_CELLS_GENERIC_INCLUDE_TC_CLK TARGET_TECH_CELLS_GENERIC_INCLUDE_TC_SRAM
    TARGET_VIVADO TARGET_XILINX NR_LANES=4 VLEN=4096 ARIANE_ACCELERATOR_PORT=1
    USE_CLUSTER=1 NR_CLUSTERS=2 PERFETTO_TRACE SIMULATION
}
# Force the clean set on BOTH the design fileset and our simset (Vivado unions
# them), then re-assert on the simset right before launch.
set saved_sources_defs [get_property verilog_define [get_filesets sources_1]]
set_property verilog_define $clean [get_filesets sources_1]
set_property verilog_define $clean $simset

set_property xsim.elaborate.debug_level off $simset
set_property xsim.simulate.log_all_signals false $simset
set_property xsim.simulate.runtime all $simset

current_fileset -simset $simset
set_property verilog_define $clean $simset
puts "AraXL standalone TB: top=tb_arasoc_extwrite"
puts "  sim_2 verilog_define = [get_property verilog_define $simset]"
puts "  sources_1 verilog_define = [get_property verilog_define [get_filesets sources_1]]"

if {[catch {launch_simulation -simset sim_2 -mode behavioral} e]} {
    # restore design fileset defines even on failure
    set_property verilog_define $saved_sources_defs [get_filesets sources_1]
    puts stderr "AraXL standalone sim failed during launch_simulation: $e"
    exit 1
}
# restore design fileset defines so the main XDMA flow is unaffected
set_property verilog_define $saved_sources_defs [get_filesets sources_1]
puts "ARAXL STANDALONE EXTWRITE SIM FINISHED"
