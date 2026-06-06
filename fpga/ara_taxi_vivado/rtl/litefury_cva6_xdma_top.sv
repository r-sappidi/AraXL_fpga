// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module litefury_cva6_xdma_top #(
    parameter int unsigned AxiDataWidth     = 64,
    parameter int unsigned XdmaAxiDataWidth = 64,
    parameter int unsigned AxiAddrWidth     = 64,
    parameter int unsigned AxiSocIdWidth    = 4
  ) (
    // Differential PCIe refclk on MGTREFCLK0_216 (F6/E6), buffered to sys_clk by
    // an IBUFDS_GTE2 below.
    input  logic        sys_clk_p,
    input  logic        sys_clk_n,
    input  logic        sys_rst_n,
    output logic [3:0]  pci_exp_txp,
    output logic [3:0]  pci_exp_txn,
    input  logic [3:0]  pci_exp_rxp,
    input  logic [3:0]  pci_exp_rxn,
    output logic        pcie_clkreq_l
  );

  // ---------------------------------------------------------------------------
  // Debug/status observation signals (formerly top-level ports).
  //
  // The LiteFury M.2 card exposes essentially no GPIO to pin these to, and
  // leaving them as unconstrained top-level outputs fails write_bitstream DRC
  // NSTD-1/UCIO-1. They carry no functional load: all results are read back
  // over PCIe via ctrl_registers (@ 0xD000_0000) and L2, never off-chip. So
  // they are kept internal and marked dont_touch so the status logic survives
  // synthesis and can be probed with an ILA during hardware bring-up.
  // ---------------------------------------------------------------------------
  (* dont_touch = "true" *) logic        user_lnk_up;
  (* dont_touch = "true" *) logic [7:0]  c2h_sts_0;
  (* dont_touch = "true" *) logic [7:0]  h2c_sts_0;
  (* dont_touch = "true" *) logic [63:0] exit_o;
  (* dont_touch = "true" *) logic [63:0] hw_cnt_en_o;

  if (AxiDataWidth != 64 || XdmaAxiDataWidth != 64) begin : gen_bad_width
    initial $error("litefury_cva6_xdma_top expects 64-bit CVA6 and XDMA AXI data widths.");
  end

  `include "axi/typedef.svh"

  // AXI flavour shared by the XDMA master and the CVA6 SoC slave port. Matches
  // cva6_xdma_soc's `ext_axi_*` interface (4-bit SoC IDs, 64-bit data).
  typedef logic [AxiAddrWidth-1:0]        axi_addr_t;
  typedef logic [AxiSocIdWidth-1:0]       axi_id_t;
  typedef logic [XdmaAxiDataWidth-1:0]    axi_data_t;
  typedef logic [XdmaAxiDataWidth/8-1:0]  axi_strb_t;
  typedef logic                           axi_user_t;
  `AXI_TYPEDEF_ALL(xdma_axi, axi_addr_t, axi_id_t, axi_data_t, axi_strb_t, axi_user_t)

  // src = XDMA master in the 125 MHz axi_aclk domain; dst = SoC slave in the
  // slow soc_clk domain. axi_cdc bridges the two.
  xdma_axi_req_t  xdma_req_src, xdma_req_dst;
  xdma_axi_resp_t xdma_resp_src, xdma_resp_dst;

  // PCIe reference clock: the LiteFury routes a differential 100 MHz refclk to
  // the GTP MGTREFCLK0 pair (F6/E6). The 7-series XDMA's single-ended sys_clk
  // port expects the buffered GT clock from an external IBUFDS_GTE2, not a
  // fabric IBUF -- driving it from a plain IOB fails IO/BUFG clock placement.
  logic sys_clk;
  IBUFDS_GTE2 refclk_ibuf (
    .O    (sys_clk),
    .ODIV2(),
    .CEB  (1'b0),
    .I    (sys_clk_p),
    .IB   (sys_clk_n)
  );

  logic axi_aclk;
  logic axi_aresetn;
  logic msi_enable;
  logic [2:0] msi_vector_width;
  logic [0:0] usr_irq_req;
  logic [0:0] usr_irq_ack;

  assign usr_irq_req   = '0;
  assign pcie_clkreq_l = 1'b0;

  // ---------------------------------------------------------------------------
  // Slow clock domain for the CVA6 SoC.
  //
  // CVA6+Ara's worst-case path (~28 ns, dominated by the FP unit) cannot meet
  // the 125 MHz XDMA AXI clock on this Artix-7 -2L part. Derive a 25 MHz SoC
  // clock from axi_aclk via an MMCM and cross the XDMA AXI master into it with
  // an axi_cdc, leaving the PCIe/XDMA datapath at full 125 MHz.
  // ---------------------------------------------------------------------------
  logic soc_clk, soc_clk_unbuf;
  logic mmcm_fb, mmcm_fb_buf;
  logic mmcm_locked;
  logic soc_rst_n;

  MMCME2_BASE #(
    .CLKIN1_PERIOD   (8.000 ),  // 125 MHz axi_aclk
    .DIVCLK_DIVIDE   (1     ),
    .CLKFBOUT_MULT_F (8.000 ),  // VCO = 1000 MHz (within -2L range)
    .CLKOUT0_DIVIDE_F(40.000)   // 1000 / 40 = 25 MHz SoC clock
  ) i_soc_mmcm (
    .CLKIN1   (axi_aclk     ),
    .CLKFBIN  (mmcm_fb_buf  ),
    .CLKFBOUT (mmcm_fb      ),
    .CLKFBOUTB(             ),
    .CLKOUT0  (soc_clk_unbuf),
    .CLKOUT0B (             ),
    .CLKOUT1  (             ),
    .CLKOUT1B (             ),
    .CLKOUT2  (             ),
    .CLKOUT2B (             ),
    .CLKOUT3  (             ),
    .CLKOUT3B (             ),
    .CLKOUT4  (             ),
    .CLKOUT5  (             ),
    .CLKOUT6  (             ),
    .LOCKED   (mmcm_locked  ),
    .PWRDWN   (1'b0         ),
    .RST      (~axi_aresetn )
  );
  BUFG i_soc_clk_bufg (.I(soc_clk_unbuf), .O(soc_clk    ));
  BUFG i_soc_fb_bufg  (.I(mmcm_fb      ), .O(mmcm_fb_buf));

  // Hold the SoC in reset until the XDMA AXI reset is released and the MMCM has
  // locked; synchronise release into the soc_clk domain.
  rstgen i_soc_rstgen (
    .clk_i      (soc_clk                   ),
    .rst_ni     (axi_aresetn & mmcm_locked ),
    .test_mode_i(1'b0                      ),
    .rst_no     (soc_rst_n                 ),
    .init_no    (                          )
  );

  logic [AxiSocIdWidth-1:0]       m_axi_awid;
  logic [AxiAddrWidth-1:0]        m_axi_awaddr;
  logic [7:0]                     m_axi_awlen;
  logic [2:0]                     m_axi_awsize;
  logic [1:0]                     m_axi_awburst;
  logic                           m_axi_awlock;
  logic [3:0]                     m_axi_awcache;
  logic [2:0]                     m_axi_awprot;
  logic                           m_axi_awvalid;
  logic                           m_axi_awready;
  logic [XdmaAxiDataWidth-1:0]    m_axi_wdata;
  logic [XdmaAxiDataWidth/8-1:0]  m_axi_wstrb;
  logic                           m_axi_wlast;
  logic                           m_axi_wvalid;
  logic                           m_axi_wready;
  logic [AxiSocIdWidth-1:0]       m_axi_bid;
  logic [1:0]                     m_axi_bresp;
  logic                           m_axi_bvalid;
  logic                           m_axi_bready;
  logic [AxiSocIdWidth-1:0]       m_axi_arid;
  logic [AxiAddrWidth-1:0]        m_axi_araddr;
  logic [7:0]                     m_axi_arlen;
  logic [2:0]                     m_axi_arsize;
  logic [1:0]                     m_axi_arburst;
  logic                           m_axi_arlock;
  logic [3:0]                     m_axi_arcache;
  logic [2:0]                     m_axi_arprot;
  logic                           m_axi_arvalid;
  logic                           m_axi_arready;
  logic [AxiSocIdWidth-1:0]       m_axi_rid;
  logic [XdmaAxiDataWidth-1:0]    m_axi_rdata;
  logic [1:0]                     m_axi_rresp;
  logic                           m_axi_rlast;
  logic                           m_axi_rvalid;
  logic                           m_axi_rready;

  xdma_1 i_xdma (
    .sys_clk(sys_clk),
    .sys_rst_n(sys_rst_n),
    .user_lnk_up(user_lnk_up),
    .pci_exp_txp(pci_exp_txp),
    .pci_exp_txn(pci_exp_txn),
    .pci_exp_rxp(pci_exp_rxp),
    .pci_exp_rxn(pci_exp_rxn),
    .axi_aclk(axi_aclk),
    .axi_aresetn(axi_aresetn),
    .usr_irq_req(usr_irq_req),
    .usr_irq_ack(usr_irq_ack),
    .msi_enable(msi_enable),
    .msi_vector_width(msi_vector_width),
    .m_axi_awready(m_axi_awready),
    .m_axi_wready(m_axi_wready),
    .m_axi_bid(m_axi_bid),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_rid(m_axi_rid),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_awid(m_axi_awid),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_awprot(m_axi_awprot),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awlock(m_axi_awlock),
    .m_axi_awcache(m_axi_awcache),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_bready(m_axi_bready),
    .m_axi_arid(m_axi_arid),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_arprot(m_axi_arprot),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arlock(m_axi_arlock),
    .m_axi_arcache(m_axi_arcache),
    .m_axi_rready(m_axi_rready),
    .cfg_mgmt_addr('0),
    .cfg_mgmt_write(1'b0),
    .cfg_mgmt_write_data('0),
    .cfg_mgmt_byte_enable('0),
    .cfg_mgmt_read(1'b0),
    .cfg_mgmt_read_data(),
    .cfg_mgmt_read_write_done(),
    .cfg_mgmt_type1_cfg_reg_access(1'b0),
    .c2h_sts_0(c2h_sts_0),
    .h2c_sts_0(h2c_sts_0)
  );

  // Pack the XDMA AXI master (axi_aclk domain) into the CDC source side.
  assign xdma_req_src.aw = '{
    id: m_axi_awid, addr: m_axi_awaddr, len: m_axi_awlen, size: m_axi_awsize,
    burst: m_axi_awburst, lock: m_axi_awlock, cache: m_axi_awcache,
    prot: m_axi_awprot, qos: '0, region: '0, atop: '0, user: '0
  };
  assign xdma_req_src.aw_valid = m_axi_awvalid;
  assign xdma_req_src.w        = '{data: m_axi_wdata, strb: m_axi_wstrb, last: m_axi_wlast, user: '0};
  assign xdma_req_src.w_valid  = m_axi_wvalid;
  assign xdma_req_src.b_ready  = m_axi_bready;
  assign xdma_req_src.ar = '{
    id: m_axi_arid, addr: m_axi_araddr, len: m_axi_arlen, size: m_axi_arsize,
    burst: m_axi_arburst, lock: m_axi_arlock, cache: m_axi_arcache,
    prot: m_axi_arprot, qos: '0, region: '0, user: '0
  };
  assign xdma_req_src.ar_valid = m_axi_arvalid;
  assign xdma_req_src.r_ready  = m_axi_rready;

  assign m_axi_awready = xdma_resp_src.aw_ready;
  assign m_axi_wready  = xdma_resp_src.w_ready;
  assign m_axi_bid     = xdma_resp_src.b.id;
  assign m_axi_bresp   = xdma_resp_src.b.resp;
  assign m_axi_bvalid  = xdma_resp_src.b_valid;
  assign m_axi_arready = xdma_resp_src.ar_ready;
  assign m_axi_rid     = xdma_resp_src.r.id;
  assign m_axi_rdata   = xdma_resp_src.r.data;
  assign m_axi_rresp   = xdma_resp_src.r.resp;
  assign m_axi_rlast   = xdma_resp_src.r.last;
  assign m_axi_rvalid  = xdma_resp_src.r_valid;

  axi_cdc #(
    .aw_chan_t (xdma_axi_aw_chan_t),
    .w_chan_t  (xdma_axi_w_chan_t ),
    .b_chan_t  (xdma_axi_b_chan_t ),
    .ar_chan_t (xdma_axi_ar_chan_t),
    .r_chan_t  (xdma_axi_r_chan_t ),
    .axi_req_t (xdma_axi_req_t    ),
    .axi_resp_t(xdma_axi_resp_t   ),
    .LogDepth  (2                 )
  ) i_xdma_axi_cdc (
    .src_clk_i (axi_aclk     ),
    .src_rst_ni(axi_aresetn  ),
    .src_req_i (xdma_req_src ),
    .src_resp_o(xdma_resp_src),
    .dst_clk_i (soc_clk      ),
    .dst_rst_ni(soc_rst_n    ),
    .dst_req_o (xdma_req_dst ),
    .dst_resp_i(xdma_resp_dst)
  );

  // Slow-domain side: SoC consumes xdma_req_dst and drives xdma_resp_dst.
  logic [AxiSocIdWidth-1:0]    s_bid, s_rid;
  logic [1:0]                  s_bresp, s_rresp;
  logic [XdmaAxiDataWidth-1:0] s_rdata;
  logic s_awready, s_wready, s_bvalid, s_arready, s_rvalid, s_rlast;

  assign xdma_resp_dst.aw_ready = s_awready;
  assign xdma_resp_dst.w_ready  = s_wready;
  assign xdma_resp_dst.b        = '{id: s_bid, resp: s_bresp, user: '0};
  assign xdma_resp_dst.b_valid  = s_bvalid;
  assign xdma_resp_dst.ar_ready = s_arready;
  assign xdma_resp_dst.r        = '{id: s_rid, data: s_rdata, resp: s_rresp, last: s_rlast, user: '0};
  assign xdma_resp_dst.r_valid  = s_rvalid;

  cva6_xdma_soc #(
    .AxiAddrWidth(AxiAddrWidth),
    .AxiDataWidth(AxiDataWidth),
    .AxiIdWidth  (5           ),
    .L2NumWords  (2**14       )
  ) i_cva6_xdma_soc (
    .clk_i(soc_clk),
    .rst_ni(soc_rst_n),
    .exit_o(exit_o),
    .hw_cnt_en_o(hw_cnt_en_o),
    .ext_axi_awid_i(xdma_req_dst.aw.id),
    .ext_axi_awaddr_i(xdma_req_dst.aw.addr),
    .ext_axi_awlen_i(xdma_req_dst.aw.len),
    .ext_axi_awsize_i(xdma_req_dst.aw.size),
    .ext_axi_awburst_i(xdma_req_dst.aw.burst),
    .ext_axi_awlock_i(xdma_req_dst.aw.lock),
    .ext_axi_awcache_i(xdma_req_dst.aw.cache),
    .ext_axi_awprot_i(xdma_req_dst.aw.prot),
    .ext_axi_awvalid_i(xdma_req_dst.aw_valid),
    .ext_axi_awready_o(s_awready),
    .ext_axi_wdata_i(xdma_req_dst.w.data),
    .ext_axi_wstrb_i(xdma_req_dst.w.strb),
    .ext_axi_wlast_i(xdma_req_dst.w.last),
    .ext_axi_wvalid_i(xdma_req_dst.w_valid),
    .ext_axi_wready_o(s_wready),
    .ext_axi_bid_o(s_bid),
    .ext_axi_bresp_o(s_bresp),
    .ext_axi_bvalid_o(s_bvalid),
    .ext_axi_bready_i(xdma_req_dst.b_ready),
    .ext_axi_arid_i(xdma_req_dst.ar.id),
    .ext_axi_araddr_i(xdma_req_dst.ar.addr),
    .ext_axi_arlen_i(xdma_req_dst.ar.len),
    .ext_axi_arsize_i(xdma_req_dst.ar.size),
    .ext_axi_arburst_i(xdma_req_dst.ar.burst),
    .ext_axi_arlock_i(xdma_req_dst.ar.lock),
    .ext_axi_arcache_i(xdma_req_dst.ar.cache),
    .ext_axi_arprot_i(xdma_req_dst.ar.prot),
    .ext_axi_arvalid_i(xdma_req_dst.ar_valid),
    .ext_axi_arready_o(s_arready),
    .ext_axi_rid_o(s_rid),
    .ext_axi_rdata_o(s_rdata),
    .ext_axi_rresp_o(s_rresp),
    .ext_axi_rlast_o(s_rlast),
    .ext_axi_rvalid_o(s_rvalid),
    .ext_axi_rready_i(xdma_req_dst.r_ready)
  );

endmodule
