# Prepare the AraXL XDMA xsim in PIPE mode.
#
# The Artix-7 XDMA endpoint (GTPE2) cannot serially train against any root-port
# BFM in xsim (GT serial models don't lock; the un-trained link floods Ara with
# X -> event storm -> OOM). PIPE mode bypasses the transceivers: EXT_PIPE_SIM
# disconnects the GTs and the EP/RP PIPE buses are cross-wired in
# board_araxl_xdma_pipe.v. We use the XDMA's own example root port
# (xilinx_pcie3_uscale_rp), whose 26b/84b PIPE interface matches the endpoint
# and whose BFM provides the TSK_XDMA_REG_* tasks the stimulus relies on.
set script_dir [file normalize [file dirname [info script]]]
set fpga_dir   [file normalize [file join $script_dir ../..]]

# Force EXT_PIPE_SIM="TRUE" in a PCIe core source (disconnects the GTs for PIPE
# sim). EXT_PIPE_SIM is never passed explicitly down the hierarchy, so the core
# default is authoritative -- and a board-level defparam into the encrypted IP
# does not take effect in xsim, so we patch the source directly.
proc force_ext_pipe_sim {path} {
    if {![file exists $path]} { puts "Warning: EXT_PIPE_SIM target missing: $path"; return 0 }
    catch {file attributes $path -permissions u+w}
    set fh [open $path r]; set d [read $fh]; close $fh
    set n [regsub -all {EXT_PIPE_SIM = "FALSE"} $d {EXT_PIPE_SIM = "TRUE"} d]
    if {$n > 0} {
        set fh [open $path w]; puts -nonewline $fh $d; close $fh
        puts "EXT_PIPE_SIM forced TRUE ($n site(s)) in [file tail $path]"
    }
    return $n
}
set main_xpr   [file normalize [file join $fpga_dir build ara_taxi ara_taxi.xpr]]
set example_dir [file normalize [file join $fpga_dir build xdma_example]]
set rp_imports [file normalize [file join $example_dir xdma_1_ex imports]]
set sim_src    [file normalize [file join $fpga_dir build araxl_xdma_sim_srcs]]

if {![file exists $main_xpr]} {
    puts stderr "Missing Vivado project: $main_xpr"
    puts stderr "Run: make -C $fpga_dir araxl-xdma-xsim-setup"
    exit 1
}

# --- 1. Enable PIPE-mode sim on the XDMA IP (exposes its PIPE ports). ---------
open_project $main_xpr
set ip [get_ips xdma_1]
if {[get_property CONFIG.pipe_sim $ip] ne "true"} {
    set_property CONFIG.pipe_sim {true} $ip
    reset_target  {simulation} $ip
    generate_target {simulation} $ip
}
# Endpoint PCIe core: enable PIPE mode (GT bypass).
force_ext_pipe_sim [file join $fpga_dir build ara_taxi ara_taxi.gen sources_1 ip xdma_1 ip_0 source xdma_1_pcie2_ip_core_top.v]

# --- 2. (Re)generate the example to harvest the UltraScale RP BFM. ------------
file delete -force $example_dir
if {[catch {open_example_project -force -dir $example_dir [get_ips xdma_1]} msg]} {
    puts stderr "OPEN_EXAMPLE_ERROR: $msg"
    exit 1
}
close_project

# --- 3. Stage BFM + board + stimulus into a clean sim source dir. ------------
file delete -force $sim_src
file mkdir $sim_src
set rp_bfm_files [list \
    xilinx_pcie_uscale_rp.v \
    pcie3_uscale_rp_top.v \
    pcie3_uscale_rp_core_top.v \
    pci_exp_usrapp_rx.v \
    pci_exp_usrapp_cfg.v \
    pci_exp_usrapp_com.v \
    pci_exp_usrapp_pl.v \
    sys_clk_gen.v \
    sys_clk_gen_ds.v \
]
foreach f $rp_bfm_files {
    file copy -force [file join $rp_imports $f] [file join $sim_src $f]
}
# Root-port PCIe core: enable PIPE mode (GT bypass).
force_ext_pipe_sim [file join $sim_src pcie3_uscale_rp_core_top.v]
# usrapp_tx needs a bigger DATA_STORE to hold the ELF payload (~24 KB).
set fh [open [file join $rp_imports pci_exp_usrapp_tx.v] r]
set tx_data [read $fh]
close $fh
if {![regsub {reg\s+\[7:0\]\s+DATA_STORE\s+\[4095:0\];} $tx_data {reg     [7:0]                   DATA_STORE [65535:0];} tx_data]} {
    puts stderr "Could not resize XDMA RP DATA_STORE in pci_exp_usrapp_tx.v"
    exit 1
}
set fh [open [file join $sim_src pci_exp_usrapp_tx.v] w]
puts -nonewline $fh $tx_data
close $fh
lappend rp_bfm_files pci_exp_usrapp_tx.v
# Include-only headers.
foreach f [list board_common.vh pci_exp_expect_tasks.vh sample_tests.vh] {
    if {[file exists [file join $rp_imports $f]]} {
        file copy -force [file join $rp_imports $f] [file join $sim_src $f]
    }
}
# Our PIPE-mode testbench top and the original AraXL stimulus (TSK_XDMA_REG_*).
file copy -force [file join $script_dir board_araxl_xdma_pipe.v] [file join $sim_src board.v]
file copy -force [file join $script_dir araxl_xdma_tests.vh]     [file join $sim_src tests.vh]

# --- 4. Wire the staged files into the main project's sim fileset. -----------
open_project $main_xpr
set simset [get_filesets sim_1]
set main_include_dirs [get_property include_dirs [get_filesets sources_1]]
set main_defines      [get_property verilog_define [get_filesets sources_1]]
foreach d {XSIM SIMULATION} {
    if {[lsearch -exact $main_defines $d] < 0} { lappend main_defines $d }
}
set stale [get_files -quiet -of_objects $simset -filter {FILE_TYPE == Verilog || FILE_TYPE == "Verilog Header" || FILE_TYPE == SystemVerilog}]
foreach s $stale {
    if {[string match "*/araxl_xdma_sim_srcs/*" [file normalize $s]]} {
        remove_files -quiet -fileset sim_1 $s
    }
}
foreach f $rp_bfm_files {
    add_files -quiet -norecurse -fileset sim_1 [file join $sim_src $f]
}
add_files -quiet -norecurse -fileset sim_1 [file join $sim_src board.v]

# Simulation-only CVA6 instruction tracer (instantiated in cva6.sv).
set tracer_srcs [list \
    [file join $fpga_dir .. .. hardware deps ariane core include instr_tracer_pkg.sv] \
    [file join $fpga_dir .. .. hardware deps ariane common local util instr_tracer_if.sv] \
    [file join $fpga_dir .. .. hardware deps ariane common local util instr_tracer.sv] \
]
foreach src $tracer_srcs {
    if {[catch {add_files -quiet -norecurse -fileset sim_1 [file normalize $src]} msg]} {
        puts "Warning: could not add tracer source $src: $msg"
    }
}

set_property include_dirs [concat $main_include_dirs [list $sim_src]] $simset
set_property verilog_define $main_defines $simset
set_property top board $simset
set_property top_lib xil_defaultlib $simset
update_compile_order -fileset sim_1

puts "AraXL XDMA xsim prepared in PIPE mode (matched UltraScale RP, GT bypassed)."
puts "  sim top : board ([file join $sim_src board.v])"
close_project
exit
