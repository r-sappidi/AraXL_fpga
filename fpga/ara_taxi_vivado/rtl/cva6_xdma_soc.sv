// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module cva6_xdma_soc import axi_pkg::*; #(
    parameter int unsigned AxiAddrWidth = 64,
    parameter int unsigned AxiDataWidth = 64,
    parameter int unsigned AxiIdWidth   = 5,
    parameter int unsigned L2NumWords   = 2**14,
    localparam int unsigned AxiSocIdWidth = AxiIdWidth - 1,
    localparam int unsigned AxiCoreIdWidth = AxiSocIdWidth - 1,
    localparam type axi_addr_t = logic [AxiAddrWidth-1:0],
    localparam type axi_data_t = logic [AxiDataWidth-1:0],
    localparam type axi_strb_t = logic [AxiDataWidth/8-1:0],
    localparam type axi_user_t = logic,
    localparam type axi_id_t   = logic [AxiIdWidth-1:0]
  ) (
    input  logic       clk_i,
    input  logic       rst_ni,
    output logic [63:0] exit_o,
    output logic [63:0] hw_cnt_en_o,
    input  logic [AxiSocIdWidth-1:0]  ext_axi_awid_i,
    input  logic [AxiAddrWidth-1:0]   ext_axi_awaddr_i,
    input  logic [7:0]                ext_axi_awlen_i,
    input  logic [2:0]                ext_axi_awsize_i,
    input  logic [1:0]                ext_axi_awburst_i,
    input  logic                      ext_axi_awlock_i,
    input  logic [3:0]                ext_axi_awcache_i,
    input  logic [2:0]                ext_axi_awprot_i,
    input  logic                      ext_axi_awvalid_i,
    output logic                      ext_axi_awready_o,
    input  logic [AxiDataWidth-1:0]   ext_axi_wdata_i,
    input  logic [AxiDataWidth/8-1:0] ext_axi_wstrb_i,
    input  logic                      ext_axi_wlast_i,
    input  logic                      ext_axi_wvalid_i,
    output logic                      ext_axi_wready_o,
    output logic [AxiSocIdWidth-1:0]  ext_axi_bid_o,
    output logic [1:0]                ext_axi_bresp_o,
    output logic                      ext_axi_bvalid_o,
    input  logic                      ext_axi_bready_i,
    input  logic [AxiSocIdWidth-1:0]  ext_axi_arid_i,
    input  logic [AxiAddrWidth-1:0]   ext_axi_araddr_i,
    input  logic [7:0]                ext_axi_arlen_i,
    input  logic [2:0]                ext_axi_arsize_i,
    input  logic [1:0]                ext_axi_arburst_i,
    input  logic                      ext_axi_arlock_i,
    input  logic [3:0]                ext_axi_arcache_i,
    input  logic [2:0]                ext_axi_arprot_i,
    input  logic                      ext_axi_arvalid_i,
    output logic                      ext_axi_arready_o,
    output logic [AxiSocIdWidth-1:0]  ext_axi_rid_o,
    output logic [AxiDataWidth-1:0]   ext_axi_rdata_o,
    output logic [1:0]                ext_axi_rresp_o,
    output logic                      ext_axi_rlast_o,
    output logic                      ext_axi_rvalid_o,
    input  logic                      ext_axi_rready_i
  );

  `include "axi/typedef.svh"
  `include "common_cells/registers.svh"

  localparam int unsigned NrAXIMasters = 2;
  localparam int unsigned NrAXISlaves  = 2;

  localparam logic [63:0] DRAMBase   = 64'h8000_0000;
  localparam logic [63:0] DRAMLength = 64'h4000_0000;
  localparam logic [63:0] CTRLBase   = 64'hD000_0000;
  localparam logic [63:0] CTRLLength = 64'h0000_1000;

  typedef enum int unsigned {
    L2MEM = 0,
    CTRL  = 1
  } axi_slaves_e;

  typedef logic [AxiSocIdWidth-1:0]  axi_soc_id_t;
  typedef logic [AxiCoreIdWidth-1:0] axi_core_id_t;

  `AXI_TYPEDEF_ALL(core_axi, axi_addr_t, axi_core_id_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(system,   axi_addr_t, axi_soc_id_t,  axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_ALL(mem_axi,  axi_addr_t, axi_id_t,      axi_data_t, axi_strb_t, axi_user_t)
  `AXI_LITE_TYPEDEF_ALL(ctrl_lite, axi_addr_t, axi_data_t, axi_strb_t)

  // Hold the CVA6 core in reset until an external loader (XDMA/PCIe) has filled
  // L2 with the program and written the core_release control register
  // (0xD0000028). Without this the core would fetch from DRAMBase the instant
  // rst_ni releases -- i.e. before the program is loaded. Only the core is
  // gated; the AXI fabric, L2 and ctrl_registers stay on rst_ni so the loader
  // can write L2 and core_release while the core waits.
  logic [63:0] core_release;
  logic        core_rst_n;
  assign core_rst_n = rst_ni & core_release[0];

  core_axi_req_t  core_axi_req;
  core_axi_resp_t core_axi_resp;
  system_req_t    [NrAXIMasters-1:0] system_axi_req;
  system_resp_t   [NrAXIMasters-1:0] system_axi_resp;
  mem_axi_req_t   [NrAXISlaves-1:0]  periph_axi_req;
  mem_axi_resp_t  [NrAXISlaves-1:0]  periph_axi_resp;

  axi_pkg::xbar_rule_64_t [NrAXISlaves-1:0] routing_rules;
  assign routing_rules = '{
    '{idx: CTRL,  start_addr: CTRLBase, end_addr: CTRLBase + CTRLLength},
    '{idx: L2MEM, start_addr: DRAMBase, end_addr: DRAMBase + DRAMLength}
  };

  localparam axi_pkg::xbar_cfg_t XBarCfg = '{
    NoSlvPorts        : NrAXIMasters,
    NoMstPorts        : NrAXISlaves,
    MaxMstTrans       : 4,
    MaxSlvTrans       : 4,
    FallThrough       : 1'b0,
    LatencyMode       : axi_pkg::CUT_MST_PORTS,
    PipelineStages    : 0,
    AxiIdWidthSlvPorts: AxiSocIdWidth,
    AxiIdUsedSlvPorts : AxiSocIdWidth,
    UniqueIds         : 1'b0,
    AxiAddrWidth      : AxiAddrWidth,
    AxiDataWidth      : AxiDataWidth,
    NoAddrRules       : NrAXISlaves
  };

  axi_xbar #(
    .Cfg          (XBarCfg                ),
    .slv_aw_chan_t(system_aw_chan_t       ),
    .mst_aw_chan_t(mem_axi_aw_chan_t      ),
    .w_chan_t     (system_w_chan_t        ),
    .slv_b_chan_t (system_b_chan_t        ),
    .mst_b_chan_t (mem_axi_b_chan_t       ),
    .slv_ar_chan_t(system_ar_chan_t       ),
    .mst_ar_chan_t(mem_axi_ar_chan_t      ),
    .slv_r_chan_t (system_r_chan_t        ),
    .mst_r_chan_t (mem_axi_r_chan_t       ),
    .slv_req_t    (system_req_t           ),
    .slv_resp_t   (system_resp_t          ),
    .mst_req_t    (mem_axi_req_t          ),
    .mst_resp_t   (mem_axi_resp_t         ),
    .rule_t       (axi_pkg::xbar_rule_64_t)
  ) i_soc_xbar (
    .clk_i                (clk_i          ),
    .rst_ni               (rst_ni         ),
    .test_i               (1'b0           ),
    .slv_ports_req_i      (system_axi_req ),
    .slv_ports_resp_o     (system_axi_resp),
    .mst_ports_req_o      (periph_axi_req ),
    .mst_ports_resp_i     (periph_axi_resp),
    .addr_map_i           (routing_rules  ),
    .en_default_mst_port_i('0             ),
    .default_mst_port_i   ('0             )
  );
  typedef ariane_pkg::ariane_cfg_t ariane_cfg_t;
  localparam ariane_cfg_t ArianeCva6XdmConfig = '{
    RASDepth             : 2,
    BTBEntries           : 32,
    BHTEntries           : 128,
    NrNonIdempotentRules : 2,
    NonIdempotentAddrBase: {64'b0, 64'b0},
    NonIdempotentLength  : {64'b0, 64'b0},
    NrExecuteRegionRules : 2,
    ExecuteRegionAddrBase: {DRAMBase, 64'h0},
    ExecuteRegionLength  : {DRAMLength, 64'h1000},
    NrCachedRegionRules  : 1,
    CachedRegionAddrBase : {DRAMBase},
    CachedRegionLength   : {DRAMLength},
    AxiCompliant         : 1'b1,
    SwapEndianess        : 1'b0,
    DmBaseAddress        : 64'h0,
    NrPMPEntries         : 0
  };


  cva6 #(
    .ArianeCfg     (ArianeCva6XdmConfig        ),
    .cvxif_req_t   (acc_pkg::accelerator_req_t ),
    .cvxif_resp_t  (acc_pkg::accelerator_resp_t),
    .AxiAddrWidth  (AxiAddrWidth               ),
    .AxiDataWidth  (AxiDataWidth               ),
    .AxiIdWidth    (AxiCoreIdWidth             ),
    .axi_ar_chan_t (core_axi_ar_chan_t         ),
    .axi_aw_chan_t (core_axi_aw_chan_t         ),
    .axi_w_chan_t  (core_axi_w_chan_t          ),
    .axi_req_t     (core_axi_req_t             ),
    .axi_rsp_t     (core_axi_resp_t            )
  ) i_cva6 (
    .clk_i       (clk_i      ),
    .rst_ni      (core_rst_n ),
    .boot_addr_i (DRAMBase   ),
    .hart_id_i   (64'b0    ),
    .irq_i       ('0       ),
    .ipi_i       ('0       ),
    .time_irq_i  ('0       ),
    .debug_req_i ('0       ),
    .rvfi_o      (         ),
    .cvxif_req_o (         ),
    .cvxif_resp_i('0       ),
    .l15_req_o   (         ),
    .l15_rtrn_i  ('0       ),
    .axi_req_o   (core_axi_req ),
    .axi_resp_i  (core_axi_resp)
  );

  assign system_axi_req[0].aw = '{
    id: {1'b0, core_axi_req.aw.id}, addr: core_axi_req.aw.addr, len: core_axi_req.aw.len,
    size: core_axi_req.aw.size, burst: core_axi_req.aw.burst, lock: core_axi_req.aw.lock,
    cache: core_axi_req.aw.cache, prot: core_axi_req.aw.prot, qos: core_axi_req.aw.qos,
    region: core_axi_req.aw.region, atop: core_axi_req.aw.atop, user: core_axi_req.aw.user
  };
  assign system_axi_req[0].aw_valid = core_axi_req.aw_valid;
  assign system_axi_req[0].w = core_axi_req.w;
  assign system_axi_req[0].w_valid = core_axi_req.w_valid;
  assign system_axi_req[0].b_ready = core_axi_req.b_ready;
  assign system_axi_req[0].ar = '{
    id: {1'b0, core_axi_req.ar.id}, addr: core_axi_req.ar.addr, len: core_axi_req.ar.len,
    size: core_axi_req.ar.size, burst: core_axi_req.ar.burst, lock: core_axi_req.ar.lock,
    cache: core_axi_req.ar.cache, prot: core_axi_req.ar.prot, qos: core_axi_req.ar.qos,
    region: core_axi_req.ar.region, user: core_axi_req.ar.user
  };
  assign system_axi_req[0].ar_valid = core_axi_req.ar_valid;
  assign system_axi_req[0].r_ready = core_axi_req.r_ready;

  assign core_axi_resp.aw_ready = system_axi_resp[0].aw_ready;
  assign core_axi_resp.w_ready  = system_axi_resp[0].w_ready;
  assign core_axi_resp.b        = '{
    id: system_axi_resp[0].b.id[AxiCoreIdWidth-1:0],
    resp: system_axi_resp[0].b.resp, user: system_axi_resp[0].b.user
  };
  assign core_axi_resp.b_valid  = system_axi_resp[0].b_valid;
  assign core_axi_resp.ar_ready = system_axi_resp[0].ar_ready;
  assign core_axi_resp.r        = '{
    id: system_axi_resp[0].r.id[AxiCoreIdWidth-1:0], data: system_axi_resp[0].r.data,
    resp: system_axi_resp[0].r.resp, last: system_axi_resp[0].r.last, user: system_axi_resp[0].r.user
  };
  assign core_axi_resp.r_valid  = system_axi_resp[0].r_valid;

  assign system_axi_req[1].aw = '{
    id: ext_axi_awid_i, addr: ext_axi_awaddr_i, len: ext_axi_awlen_i,
    size: ext_axi_awsize_i, burst: ext_axi_awburst_i, lock: ext_axi_awlock_i,
    cache: ext_axi_awcache_i, prot: ext_axi_awprot_i, qos: '0, region: '0,
    atop: '0, user: '0
  };
  assign system_axi_req[1].aw_valid = ext_axi_awvalid_i;
  assign system_axi_req[1].w = '{data: ext_axi_wdata_i, strb: ext_axi_wstrb_i, last: ext_axi_wlast_i, user: '0};
  assign system_axi_req[1].w_valid = ext_axi_wvalid_i;
  assign system_axi_req[1].b_ready = ext_axi_bready_i;
  assign system_axi_req[1].ar = '{
    id: ext_axi_arid_i, addr: ext_axi_araddr_i, len: ext_axi_arlen_i,
    size: ext_axi_arsize_i, burst: ext_axi_arburst_i, lock: ext_axi_arlock_i,
    cache: ext_axi_arcache_i, prot: ext_axi_arprot_i, qos: '0, region: '0,
    user: '0
  };
  assign system_axi_req[1].ar_valid = ext_axi_arvalid_i;
  assign system_axi_req[1].r_ready = ext_axi_rready_i;

  assign ext_axi_awready_o = system_axi_resp[1].aw_ready;
  assign ext_axi_wready_o  = system_axi_resp[1].w_ready;
  assign ext_axi_bid_o     = system_axi_resp[1].b.id;
  assign ext_axi_bresp_o   = system_axi_resp[1].b.resp;
  assign ext_axi_bvalid_o  = system_axi_resp[1].b_valid;
  assign ext_axi_arready_o = system_axi_resp[1].ar_ready;
  assign ext_axi_rid_o     = system_axi_resp[1].r.id;
  assign ext_axi_rdata_o   = system_axi_resp[1].r.data;
  assign ext_axi_rresp_o   = system_axi_resp[1].r.resp;
  assign ext_axi_rlast_o   = system_axi_resp[1].r.last;
  assign ext_axi_rvalid_o  = system_axi_resp[1].r_valid;

  mem_axi_req_t  l2mem_axi_req_wo_atomics;
  mem_axi_resp_t l2mem_axi_resp_wo_atomics;

  axi_atop_filter #(
    .AxiIdWidth     (AxiIdWidth      ),
    // MUST be > 0: with the default 0 the filter never forwards AW (its
    // feed-through guard `w_cnt < AxiMaxWriteTxns` is always false), so writes to
    // L2 never reach axi_to_mem and w_ready jams -- the DMA-to-SoC write stall.
    .AxiMaxWriteTxns (4              ),
    .axi_req_t      (mem_axi_req_t   ),
    .axi_resp_t     (mem_axi_resp_t  )
  ) i_l2mem_atop_filter (
    .clk_i     (clk_i                       ),
    .rst_ni    (rst_ni                      ),
    .slv_req_i (periph_axi_req[L2MEM]       ),
    .slv_resp_o(periph_axi_resp[L2MEM]      ),
    .mst_req_o (l2mem_axi_req_wo_atomics    ),
    .mst_resp_i(l2mem_axi_resp_wo_atomics   )
  );

  logic                      l2_req;
  logic                      l2_we;
  logic [AxiAddrWidth-1:0]   l2_addr;
  logic [AxiDataWidth/8-1:0] l2_be;
  logic [AxiDataWidth-1:0]   l2_wdata;
  logic [AxiDataWidth-1:0]   l2_rdata;
  logic                      l2_rvalid;

  axi_to_mem #(
    .AddrWidth (AxiAddrWidth   ),
    .DataWidth (AxiDataWidth   ),
    .IdWidth   (AxiIdWidth     ),
    .NumBanks  (1              ),
    .axi_req_t (mem_axi_req_t  ),
    .axi_resp_t(mem_axi_resp_t )
  ) i_axi_to_mem (
    .clk_i       (clk_i                       ),
    .rst_ni      (rst_ni                      ),
    .busy_o      (                            ),
    .axi_req_i   (l2mem_axi_req_wo_atomics    ),
    .axi_resp_o  (l2mem_axi_resp_wo_atomics   ),
    .mem_req_o   (l2_req                      ),
    .mem_gnt_i   (l2_req                      ),
    .mem_we_o    (l2_we                       ),
    .mem_addr_o  (l2_addr                     ),
    .mem_strb_o  (l2_be                       ),
    .mem_wdata_o (l2_wdata                    ),
    .mem_rdata_i (l2_rdata                    ),
    .mem_rvalid_i(l2_rvalid                   )
  );

  tc_sram #(
    .NumWords (L2NumWords  ),
    .DataWidth(AxiDataWidth),
    .ByteWidth(8           ),
    .NumPorts (1           )
  ) i_l2_sram (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .req_i  (l2_req),
    .we_i   (l2_we),
    .addr_i (l2_addr[$clog2(L2NumWords)-1+$clog2(AxiDataWidth/8):$clog2(AxiDataWidth/8)]),
    .wdata_i(l2_wdata),
    .be_i   (l2_be),
    .rdata_o(l2_rdata)
  );

  `FF(l2_rvalid, l2_req, 1'b0, clk_i, rst_ni)

  ctrl_lite_req_t  ctrl_lite_req;
  ctrl_lite_resp_t ctrl_lite_resp;

  axi_to_axi_lite #(
    .AxiAddrWidth   (AxiAddrWidth      ),
    .AxiDataWidth   (AxiDataWidth      ),
    .AxiIdWidth     (AxiIdWidth        ),
    .AxiUserWidth   (1                 ),
    .AxiMaxWriteTxns(1                 ),
    .AxiMaxReadTxns (1                 ),
    .FallThrough    (1'b0              ),
    .full_req_t     (mem_axi_req_t     ),
    .full_resp_t    (mem_axi_resp_t    ),
    .lite_req_t     (ctrl_lite_req_t   ),
    .lite_resp_t    (ctrl_lite_resp_t  )
  ) i_axi_to_axi_lite_ctrl (
    .clk_i     (clk_i                 ),
    .rst_ni    (rst_ni                ),
    .slv_req_i (periph_axi_req[CTRL]  ),
    .slv_resp_o(periph_axi_resp[CTRL] ),
    .mst_req_o (ctrl_lite_req         ),
    .mst_resp_i(ctrl_lite_resp        )
  );

  logic [63:0] dram_base_address;
  logic [63:0] dram_end_address;
  logic [63:0] event_trigger;

  ctrl_registers #(
    .DataWidth            (AxiDataWidth      ),
    .DRAMBaseAddr         (DRAMBase[AxiDataWidth-1:0]),
    .DRAMLength           (DRAMLength[AxiDataWidth-1:0]),
    .axi_lite_req_t       (ctrl_lite_req_t   ),
    .axi_lite_resp_t      (ctrl_lite_resp_t  )
  ) i_ctrl_registers (
    .clk_i                (clk_i             ),
    .rst_ni               (rst_ni            ),
    .axi_lite_slave_req_i (ctrl_lite_req     ),
    .axi_lite_slave_resp_o(ctrl_lite_resp    ),
    .exit_o               (exit_o            ),
    .dram_base_addr_o  (dram_base_address ),
    .dram_end_addr_o   (dram_end_address  ),
    .event_trigger_o      (event_trigger     ),
    .hw_cnt_en_o          (hw_cnt_en_o       ),
    .core_release_o       (core_release      )
  );

endmodule
