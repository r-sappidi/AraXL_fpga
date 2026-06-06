# Repo-level Vivado project generator for Ara + Taxi.

proc script_dir {} {
    return [file normalize [file dirname [info script]]]
}

proc repo_root {} {
    return [file normalize [file join [script_dir] ../..]]
}

proc add_if_exists {fileset path} {
    if {[file exists $path]} {
        add_files -fileset $fileset $path
    } else {
        puts "Warning: missing source path $path"
    }
}

proc add_sv_glob {fileset root rel_glob} {
    foreach path [glob -nocomplain -directory $root $rel_glob] {
        add_if_exists $fileset $path
    }
}

proc add_ara_sources_with_bender {root build_dir nr_lanes vlen nr_clusters} {
    set bender [file join $root hardware bender]
    set out_tcl [file join $build_dir ara_bender_sources.tcl]

    if {![file executable $bender]} {
        puts "Warning: hardware/bender is not executable; adding direct Ara RTL only"
        return 0
    }

    set defs [list \
        --define "NR_LANES=$nr_lanes" \
        --define "VLEN=$vlen" \
        --define ARIANE_ACCELERATOR_PORT=1 \
        --define USE_CLUSTER=1 \
        --define "NR_CLUSTERS=$nr_clusters" \
        --define PERFETTO_TRACE \
    ]
    set targets [list \
        -t rtl \
        -t cv64a6_imafdcv_sv39 \
        -t tech_cells_generic_include_tc_sram \
        -t tech_cells_generic_include_tc_clk \
    ]

    set cwd [pwd]
    cd $root
    set cmd [concat [list $bender script vivado] $targets $defs]
    puts "Running: $cmd"
    set rc [catch {exec {*}$cmd > $out_tcl} msg]

    if {$rc != 0} {
        puts "Warning: Bender reported: $msg"
        if {[file exists $out_tcl] && [file size $out_tcl] > 0} {
            puts "Warning: using generated Bender source list despite warning"
            source $out_tcl
            cd $cwd
            return 1
        }
        cd $cwd
        puts "Warning: Bender source generation failed; adding direct Ara RTL only"
        return 0
    }

    source $out_tcl
    cd $cwd
    return 1
}

proc add_direct_ara_sources {root} {
    set files [list \
        hardware/include/rvv_pkg.sv \
        hardware/include/ara_pkg.sv \
        hardware/src/cva6_cut.sv \
        hardware/src/req_fork_cut.sv \
        hardware/src/axi_to_mem.sv \
        hardware/src/ctrl_registers.sv \
        hardware/src/cva6_accel_first_pass_decoder.sv \
        hardware/src/ara_dispatcher.sv \
        hardware/src/ara_sequencer.sv \
        hardware/src/axi_inval_filter.sv \
        hardware/src/lane/lane_sequencer.sv \
        hardware/src/lane/operand_queue.sv \
        hardware/src/lane/operand_requester.sv \
        hardware/src/lane/simd_alu.sv \
        hardware/src/lane/simd_div.sv \
        hardware/src/lane/simd_mul.sv \
        hardware/src/lane/vector_regfile.sv \
        hardware/src/lane/power_gating_generic.sv \
        hardware/src/lane/power_gating_tech.sv \
        hardware/src/masku/masku.sv \
        hardware/src/sldu/p2_stride_gen.sv \
        hardware/src/sldu/ring_router.sv \
        hardware/src/sldu/sldu_op_dp.sv \
        hardware/src/sldu/sldu.sv \
        hardware/src/vlsu/addrgen.sv \
        hardware/src/vlsu/vldu.sv \
        hardware/src/vlsu/vstu.sv \
        hardware/src/vlsu/global_ldst.sv \
        hardware/src/vlsu/align_stage.sv \
        hardware/src/vlsu/shuffle_stage.sv \
        hardware/src/lane/operand_queues_stage.sv \
        hardware/src/lane/valu.sv \
        hardware/src/lane/vmfpu.sv \
        hardware/src/lane/fixed_p_rounding.sv \
        hardware/src/vlsu/vlsu.sv \
        hardware/src/lane/vector_fus_stage.sv \
        hardware/src/lane/lane.sv \
        hardware/src/ara.sv \
        hardware/src/ara_macro.sv \
        hardware/src/ara_cluster.sv \
        hardware/src/ara_system.sv \
        hardware/src/ara_soc.sv \
    ]

    foreach rel $files {
        add_if_exists sources_1 [file join $root $rel]
    }
}

proc add_ariane_fpga_support {root} {
    add_if_exists sources_1 [file join $root hardware deps ariane vendor pulp-platform fpga-support rtl SyncSpRamBeNx64.sv]
}

proc add_taxi_sources {root} {
    set taxi [file join $root hardware taxi taxi src]

    foreach dir [list \
        axis/rtl \
        axi/rtl \
        dma/rtl \
        pcie/rtl \
        sync/rtl \
        prim/rtl \
    ] {
        add_sv_glob sources_1 [file join $taxi $dir] *.sv
    }
}

proc add_fpga_sources {root} {
    add_sv_glob sources_1 [file join $root fpga ara_taxi_vivado rtl] *.sv
}

proc add_litefury_constraints {root} {
    set xdc [file join $root fpga ara_taxi_vivado xdc litefury_pcie.xdc]
    add_if_exists constrs_1 $xdc
    if {[file exists $xdc]} {
        set_property PROCESSING_ORDER LATE [get_files -of_objects [get_filesets constrs_1] $xdc]
    }

    set gt_locs_tcl [file join $root fpga ara_taxi_vivado apply_litefury_gt_locs.tcl]
    if {[file exists $gt_locs_tcl] && [llength [get_runs impl_1]] > 0} {
        set_property STEPS.PLACE_DESIGN.TCL.PRE $gt_locs_tcl [get_runs impl_1]
    }
}

proc create_artix7_xdma_ip {} {
    create_ip -name xdma -vendor xilinx.com -library ip -version 4.2 -module_name xdma_1
    set_property -dict [list \
        CONFIG.mode_selection {Advanced} \
        CONFIG.pl_link_cap_max_link_width {X4} \
        CONFIG.axi_data_width {64_bit} \
        CONFIG.axilite_master_en {false} \
        CONFIG.xdma_pcie_64bit_en {true} \
        CONFIG.pf0_device_id {7014} \
        CONFIG.pf0_subsystem_vendor_id {10EE} \
        CONFIG.pf0_subsystem_id {0007} \
        CONFIG.pf0_msi_enabled {true} \
        CONFIG.pf0_msi_cap_multimsgcap {1_vector} \
        CONFIG.pf0_msix_enabled {false} \
        CONFIG.xdma_rnum_chnl {1} \
        CONFIG.xdma_wnum_chnl {1} \
        CONFIG.xdma_rnum_rids {2} \
        CONFIG.xdma_wnum_rids {2} \
        CONFIG.xdma_num_usr_irq {1} \
        CONFIG.axi_id_width {4} \
        CONFIG.xdma_sts_ports {true} \
        CONFIG.xdma_dsc_bypass {false} \
        CONFIG.disable_gt_loc {true} \
    ] [get_ips xdma_1]
    generate_target all [get_ips xdma_1]
    catch {config_ip_cache -export [get_ips -all xdma_1]}
    export_ip_user_files -of_objects [get_files -of_objects [get_filesets sources_1] */xdma_1.xci] -no_script -sync -force -quiet
    catch {create_ip_run [get_files -of_objects [get_filesets sources_1] */xdma_1.xci]}
}

if {$argc < 8} {
    puts "Usage: create_project.tcl <project> <part> <top> <nr_lanes> <vlen> <nr_clusters> <create_pcie_ip> <build_dir>"
    exit 1
}

set project        [lindex $argv 0]
set part           [lindex $argv 1]
set top            [lindex $argv 2]
set nr_lanes       [lindex $argv 3]
set vlen           [lindex $argv 4]
set nr_clusters    [lindex $argv 5]
set create_pcie_ip [lindex $argv 6]
set build_dir_arg  [lindex $argv 7]

set root [repo_root]
set build_dir [file normalize [file join [script_dir] $build_dir_arg]]
file mkdir $build_dir

create_project -force $project [file join $build_dir $project] -part $part

set_property target_language Verilog [current_project]
set_property source_mgmt_mode All [current_project]

set defines [list \
    "NR_LANES=$nr_lanes" \
    "VLEN=$vlen" \
    ARIANE_ACCELERATOR_PORT=1 \
    USE_CLUSTER=1 \
    "NR_CLUSTERS=$nr_clusters" \
    PERFETTO_TRACE \
]
set_property verilog_define $defines [current_fileset]

set include_dirs [list \
    [file join $root hardware include] \
    [file join $root hardware deps axi include] \
    [file join $root hardware deps apb include] \
    [file join $root hardware deps common_cells include] \
    [file join $root hardware deps ariane core include] \
    [file join $root hardware deps ariane corev_apu include] \
    [file join $root hardware deps ariane common local include] \
]
set_property include_dirs $include_dirs [current_fileset]

if {![add_ara_sources_with_bender $root $build_dir $nr_lanes $vlen $nr_clusters]} {
    add_direct_ara_sources $root
}

add_ariane_fpga_support $root
add_taxi_sources $root
add_fpga_sources $root

if {$create_pcie_ip} {
    if {[string match {xc7a*} $part]} {
        add_litefury_constraints $root
        create_artix7_xdma_ip
    } else {
        set pcie_ip_tcl [file join $root hardware taxi taxi src cndm board VCU118 fpga ip pcie4_uscale_plus_0.tcl]
        if {[file exists $pcie_ip_tcl]} {
            source $pcie_ip_tcl
        } else {
            puts "Warning: missing PCIe IP TCL $pcie_ip_tcl"
        }
    }
}

set_property top $top [current_fileset]
update_compile_order -fileset sources_1

puts "Created $project for part $part with top $top"
