# Regenerate the XDMA example design (now that pipe_sim=true) purely to harvest
# the pristine board.v PIPE interconnect (EXT_PIPE_SIM cross-wire + pipe clock)
# as a template for our PIPE-mode board_araxl_xdma board.
set script_dir [file normalize [file dirname [info script]]]
set fpga_dir   [file normalize [file join $script_dir ../..]]
set main_xpr   [file normalize [file join $fpga_dir build ara_taxi ara_taxi.xpr]]
set ref_dir    [file normalize [file join $fpga_dir build xdma_pipe_ref]]

open_project $main_xpr
file delete -force $ref_dir
file mkdir $ref_dir
if {[catch {open_example_project -force -dir $ref_dir [get_ips xdma_1]} msg]} {
    puts "OPEN_EXAMPLE_ERROR: $msg"
    exit 1
}
close_project
set board_v [file join $ref_dir xdma_1_ex imports board.v]
if {[file exists $board_v]} {
    puts "PIPE_REF_BOARD=$board_v"
} else {
    puts "PIPE_REF_BOARD_MISSING"
}
exit
