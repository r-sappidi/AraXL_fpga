// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`ifndef NR_LANES
`define NR_LANES 2
`endif
`ifndef NR_CLUSTERS
`define NR_CLUSTERS 1
`endif

module litefury_araxl_xdma_top #(
    parameter int unsigned NrLanes    = `NR_LANES,
    parameter int unsigned NrClusters = `NR_CLUSTERS,
    parameter int unsigned AxiDataWidth = 32 * NrLanes * NrClusters,
    parameter int unsigned XdmaAxiDataWidth = 64,
    parameter int unsigned AxiAddrWidth = 64,
    parameter int unsigned AxiSocIdWidth = 4
  ) (
`ifdef XSIM
    // In PIPE-mode sim there is no GT; the testbench drives the buffered clock
    // directly, so sys_clk stays a plain single-ended input.
    input  logic       sys_clk,
`else
    // Synthesis/implementation: differential PCIe refclk on MGTREFCLK0_216
    // (F6/E6), buffered to sys_clk by an IBUFDS_GTE2 below.
    input  logic       sys_clk_p,
    input  logic       sys_clk_n,
`endif
    input  logic       sys_rst_n,
    output logic       user_lnk_up,
    output logic [3:0] pci_exp_txp,
    output logic [3:0] pci_exp_txn,
    input  logic [3:0] pci_exp_rxp,
    input  logic [3:0] pci_exp_rxn,
    output logic       pcie_clkreq_l,
    output logic [7:0] c2h_sts_0,
    output logic [7:0] h2c_sts_0,
    output logic [63:0] exit_o,
    output logic [63:0] hw_cnt_en_o
`ifdef XSIM
    // PIPE-mode simulation interface (exposed only when the XDMA IP is built
    // with pipe_sim=true). Lets the testbench connect the endpoint to a root
    // port at the PIPE level, bypassing the GT serdes (which cannot train in
    // xsim). Not present in synthesis (pipe_sim=false there).
    ,
    input  logic [25:0] common_commands_in,
    input  logic [83:0] pipe_rx_0_sigs,
    input  logic [83:0] pipe_rx_1_sigs,
    input  logic [83:0] pipe_rx_2_sigs,
    input  logic [83:0] pipe_rx_3_sigs,
    input  logic [83:0] pipe_rx_4_sigs,
    input  logic [83:0] pipe_rx_5_sigs,
    input  logic [83:0] pipe_rx_6_sigs,
    input  logic [83:0] pipe_rx_7_sigs,
    output logic [25:0] common_commands_out,
    output logic [83:0] pipe_tx_0_sigs,
    output logic [83:0] pipe_tx_1_sigs,
    output logic [83:0] pipe_tx_2_sigs,
    output logic [83:0] pipe_tx_3_sigs,
    output logic [83:0] pipe_tx_4_sigs,
    output logic [83:0] pipe_tx_5_sigs,
    output logic [83:0] pipe_tx_6_sigs,
    output logic [83:0] pipe_tx_7_sigs
`endif
  );

  `include "axi/typedef.svh"

  typedef logic [AxiAddrWidth-1:0]       axi_addr_t;
  typedef logic [AxiSocIdWidth-1:0]      axi_id_t;
  typedef logic [XdmaAxiDataWidth-1:0]   xdma_axi_data_t;
  typedef logic [XdmaAxiDataWidth/8-1:0] xdma_axi_strb_t;
  typedef logic [AxiDataWidth-1:0]       ara_axi_data_t;
  typedef logic [AxiDataWidth/8-1:0]     ara_axi_strb_t;
  typedef logic                          axi_user_t;

  `AXI_TYPEDEF_AW_CHAN_T(ext_axi_aw_chan_t, axi_addr_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_W_CHAN_T(xdma_axi_w_chan_t, xdma_axi_data_t, xdma_axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_W_CHAN_T(ara_axi_w_chan_t, ara_axi_data_t, ara_axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T(ext_axi_b_chan_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_AR_CHAN_T(ext_axi_ar_chan_t, axi_addr_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(xdma_axi_r_chan_t, xdma_axi_data_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(ara_axi_r_chan_t, ara_axi_data_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_REQ_T(xdma_axi_req_t, ext_axi_aw_chan_t, xdma_axi_w_chan_t, ext_axi_ar_chan_t)
  `AXI_TYPEDEF_RESP_T(xdma_axi_resp_t, ext_axi_b_chan_t, xdma_axi_r_chan_t)
  `AXI_TYPEDEF_REQ_T(ara_axi_req_t, ext_axi_aw_chan_t, ara_axi_w_chan_t, ext_axi_ar_chan_t)
  `AXI_TYPEDEF_RESP_T(ara_axi_resp_t, ext_axi_b_chan_t, ara_axi_r_chan_t)

`ifndef XSIM
  // 7-series XDMA sys_clk must be driven by the GT refclk buffer, not a fabric
  // IBUF, or IO/BUFG clock placement fails (Place 30-574).
  logic sys_clk;
  IBUFDS_GTE2 refclk_ibuf (
    .O    (sys_clk),
    .ODIV2(),
    .CEB  (1'b0),
    .I    (sys_clk_p),
    .IB   (sys_clk_n)
  );
`endif

  logic axi_aclk;
  logic user_clk;
  logic axi_aresetn;
  logic msi_enable;
  logic [2:0] msi_vector_width;
  logic [0:0] usr_irq_req;
  logic [0:0] usr_irq_ack;

  assign usr_irq_req = '0;
  assign user_clk = axi_aclk;
  assign pcie_clkreq_l = 1'b0;

  xdma_axi_req_t  xdma_axi_req;
  xdma_axi_resp_t xdma_axi_resp;
  ara_axi_req_t   ara_axi_req;
  ara_axi_resp_t  ara_axi_resp;

  logic [AxiSocIdWidth-1:0]  m_axi_awid;
  logic [AxiAddrWidth-1:0]   m_axi_awaddr;
  logic [7:0]                m_axi_awlen;
  logic [2:0]                m_axi_awsize;
  logic [1:0]                m_axi_awburst;
  logic                      m_axi_awlock;
  logic [3:0]                m_axi_awcache;
  logic [2:0]                m_axi_awprot;
  logic                      m_axi_awvalid;
  logic                      m_axi_awready;
  logic [XdmaAxiDataWidth-1:0]   m_axi_wdata;
  logic [XdmaAxiDataWidth/8-1:0] m_axi_wstrb;
  logic                      m_axi_wlast;
  logic                      m_axi_wvalid;
  logic                      m_axi_wready;
  logic [AxiSocIdWidth-1:0]  m_axi_bid;
  logic [1:0]                m_axi_bresp;
  logic                      m_axi_bvalid;
  logic                      m_axi_bready;
  logic [AxiSocIdWidth-1:0]  m_axi_arid;
  logic [AxiAddrWidth-1:0]   m_axi_araddr;
  logic [7:0]                m_axi_arlen;
  logic [2:0]                m_axi_arsize;
  logic [1:0]                m_axi_arburst;
  logic                      m_axi_arlock;
  logic [3:0]                m_axi_arcache;
  logic [2:0]                m_axi_arprot;
  logic                      m_axi_arvalid;
  logic                      m_axi_arready;
  logic [AxiSocIdWidth-1:0]  m_axi_rid;
  logic [XdmaAxiDataWidth-1:0]   m_axi_rdata;
  logic [1:0]                m_axi_rresp;
  logic                      m_axi_rlast;
  logic                      m_axi_rvalid;
  logic                      m_axi_rready;

  logic uart_penable;
  logic uart_pwrite;
  logic [31:0] uart_paddr;
  logic uart_psel;
  logic [31:0] uart_pwdata;

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
`ifdef XSIM
    ,
    .common_commands_in(common_commands_in),
    .pipe_rx_0_sigs(pipe_rx_0_sigs),
    .pipe_rx_1_sigs(pipe_rx_1_sigs),
    .pipe_rx_2_sigs(pipe_rx_2_sigs),
    .pipe_rx_3_sigs(pipe_rx_3_sigs),
    .pipe_rx_4_sigs(pipe_rx_4_sigs),
    .pipe_rx_5_sigs(pipe_rx_5_sigs),
    .pipe_rx_6_sigs(pipe_rx_6_sigs),
    .pipe_rx_7_sigs(pipe_rx_7_sigs),
    .common_commands_out(common_commands_out),
    .pipe_tx_0_sigs(pipe_tx_0_sigs),
    .pipe_tx_1_sigs(pipe_tx_1_sigs),
    .pipe_tx_2_sigs(pipe_tx_2_sigs),
    .pipe_tx_3_sigs(pipe_tx_3_sigs),
    .pipe_tx_4_sigs(pipe_tx_4_sigs),
    .pipe_tx_5_sigs(pipe_tx_5_sigs),
    .pipe_tx_6_sigs(pipe_tx_6_sigs),
    .pipe_tx_7_sigs(pipe_tx_7_sigs)
`endif
  );

  always_comb begin
    xdma_axi_req = '0;
    xdma_axi_req.aw.id    = m_axi_awid;
    xdma_axi_req.aw.addr  = m_axi_awaddr;
    xdma_axi_req.aw.len   = m_axi_awlen;
    xdma_axi_req.aw.size  = m_axi_awsize;
    xdma_axi_req.aw.burst = m_axi_awburst;
    xdma_axi_req.aw.lock  = m_axi_awlock;
    xdma_axi_req.aw.cache = m_axi_awcache;
    xdma_axi_req.aw.prot  = m_axi_awprot;
    xdma_axi_req.aw_valid = m_axi_awvalid;
    xdma_axi_req.w.data   = m_axi_wdata;
    xdma_axi_req.w.strb   = m_axi_wstrb;
    xdma_axi_req.w.last   = m_axi_wlast;
    xdma_axi_req.w_valid  = m_axi_wvalid;
    xdma_axi_req.b_ready  = m_axi_bready;
    xdma_axi_req.ar.id    = m_axi_arid;
    xdma_axi_req.ar.addr  = m_axi_araddr;
    xdma_axi_req.ar.len   = m_axi_arlen;
    xdma_axi_req.ar.size  = m_axi_arsize;
    xdma_axi_req.ar.burst = m_axi_arburst;
    xdma_axi_req.ar.lock  = m_axi_arlock;
    xdma_axi_req.ar.cache = m_axi_arcache;
    xdma_axi_req.ar.prot  = m_axi_arprot;
    xdma_axi_req.ar_valid = m_axi_arvalid;
    xdma_axi_req.r_ready  = m_axi_rready;
  end

  assign m_axi_awready = xdma_axi_resp.aw_ready;
  assign m_axi_wready  = xdma_axi_resp.w_ready;
  assign m_axi_bid     = xdma_axi_resp.b.id;
  assign m_axi_bresp   = xdma_axi_resp.b.resp;
  assign m_axi_bvalid  = xdma_axi_resp.b_valid;
  assign m_axi_arready = xdma_axi_resp.ar_ready;
  assign m_axi_rid     = xdma_axi_resp.r.id;
  assign m_axi_rdata   = xdma_axi_resp.r.data;
  assign m_axi_rresp   = xdma_axi_resp.r.resp;
  assign m_axi_rlast   = xdma_axi_resp.r.last;
  assign m_axi_rvalid  = xdma_axi_resp.r_valid;

  axi_dw_converter #(
    .AxiMaxReads        (2                 ),
    .AxiSlvPortDataWidth(XdmaAxiDataWidth  ),
    .AxiMstPortDataWidth(AxiDataWidth      ),
    .AxiAddrWidth       (AxiAddrWidth      ),
    .AxiIdWidth         (AxiSocIdWidth     ),
    .aw_chan_t          (ext_axi_aw_chan_t ),
    .mst_w_chan_t       (ara_axi_w_chan_t  ),
    .slv_w_chan_t       (xdma_axi_w_chan_t ),
    .b_chan_t           (ext_axi_b_chan_t  ),
    .ar_chan_t          (ext_axi_ar_chan_t ),
    .mst_r_chan_t       (ara_axi_r_chan_t  ),
    .slv_r_chan_t       (xdma_axi_r_chan_t ),
    .axi_mst_req_t      (ara_axi_req_t     ),
    .axi_mst_resp_t     (ara_axi_resp_t    ),
    .axi_slv_req_t      (xdma_axi_req_t    ),
    .axi_slv_resp_t     (xdma_axi_resp_t   )
  ) i_xdma_to_ara_dwc (
    .clk_i     (axi_aclk      ),
    .rst_ni    (axi_aresetn   ),
    .slv_req_i (xdma_axi_req  ),
    .slv_resp_o(xdma_axi_resp ),
    .mst_req_o (ara_axi_req   ),
    .mst_resp_i(ara_axi_resp  )
  );

`ifdef XSIM_XDMA_AXI_STUB
  logic [AxiSocIdWidth-1:0] stub_aw_id_q [0:15];
  logic [AxiAddrWidth-1:0]  stub_aw_addr_q [0:15];
  logic [7:0]               stub_aw_len_q [0:15];
  logic [3:0]               stub_aw_wptr_q, stub_aw_rptr_q;
  logic [4:0]               stub_aw_count_q;
  logic [63:0]              stub_l2_bytes_q;
  logic [63:0]              stub_ctrl_bytes_q;
  logic                     stub_core_release_q;
  logic                     stub_b_valid_q;
  logic [AxiSocIdWidth-1:0] stub_b_id_q;

  function automatic logic stub_data_nonzero(
    input ara_axi_data_t data,
    input ara_axi_strb_t strb
  );
    stub_data_nonzero = 1'b0;
    for (int unsigned i = 0; i < AxiDataWidth/8; i++) begin
      if (strb[i] && data[i*8 +: 8] != 8'h00) begin
        stub_data_nonzero = 1'b1;
      end
    end
  endfunction

  function automatic logic [63:0] stub_count_strb(input ara_axi_strb_t strb);
    stub_count_strb = 64'b0;
    for (int unsigned i = 0; i < AxiDataWidth/8; i++) begin
      if (strb[i]) begin
        stub_count_strb = stub_count_strb + 64'd1;
      end
    end
  endfunction

  assign ara_axi_resp.aw_ready = (stub_aw_count_q < 5'd16);
  assign ara_axi_resp.w_ready  = (stub_aw_count_q != 5'd0);
  assign ara_axi_resp.b_valid  = stub_b_valid_q;
  assign ara_axi_resp.b.id     = stub_b_id_q;
  assign ara_axi_resp.b.resp   = 2'b00;
  assign ara_axi_resp.b.user   = '0;
  assign ara_axi_resp.ar_ready = 1'b1;
  assign ara_axi_resp.r_valid  = ara_axi_req.ar_valid;
  assign ara_axi_resp.r.id     = ara_axi_req.ar.id;
  assign ara_axi_resp.r.data   = '0;
  assign ara_axi_resp.r.resp   = 2'b00;
  assign ara_axi_resp.r.last   = 1'b1;
  assign ara_axi_resp.r.user   = '0;
  assign exit_o                = {63'b0, stub_core_release_q};
  assign hw_cnt_en_o           = 64'b0;

  always_ff @(posedge axi_aclk or negedge axi_aresetn) begin
    if (!axi_aresetn) begin
      stub_aw_wptr_q       <= '0;
      stub_aw_rptr_q       <= '0;
      stub_aw_count_q      <= '0;
      stub_l2_bytes_q      <= 64'b0;
      stub_ctrl_bytes_q    <= 64'b0;
      stub_core_release_q  <= 1'b0;
      stub_b_valid_q       <= 1'b0;
      stub_b_id_q          <= '0;
    end else begin
      if (stub_b_valid_q && ara_axi_req.b_ready) begin
        stub_b_valid_q <= 1'b0;
      end

      if (ara_axi_req.aw_valid && ara_axi_resp.aw_ready) begin
        stub_aw_id_q[stub_aw_wptr_q]   <= ara_axi_req.aw.id;
        stub_aw_addr_q[stub_aw_wptr_q] <= ara_axi_req.aw.addr;
        stub_aw_len_q[stub_aw_wptr_q]  <= ara_axi_req.aw.len;
        stub_aw_wptr_q                 <= stub_aw_wptr_q + 4'd1;
        stub_aw_count_q                <= stub_aw_count_q + 5'd1;
        $display("[%t] XDMA-STUB AW addr=%h len=%0d size=%0d id=%h",
                 $realtime, ara_axi_req.aw.addr, ara_axi_req.aw.len,
                 ara_axi_req.aw.size, ara_axi_req.aw.id);
      end

      if (ara_axi_req.w_valid && ara_axi_resp.w_ready) begin
        if (stub_aw_addr_q[stub_aw_rptr_q] >= 64'h0000_0000_8000_0000 &&
            stub_aw_addr_q[stub_aw_rptr_q] <  64'h0000_0000_C000_0000) begin
          stub_l2_bytes_q <= stub_l2_bytes_q + stub_count_strb(ara_axi_req.w.strb);
        end else if (stub_aw_addr_q[stub_aw_rptr_q] >= 64'h0000_0000_D000_0000 &&
                     stub_aw_addr_q[stub_aw_rptr_q] <  64'h0000_0000_D000_1000) begin
          stub_ctrl_bytes_q <= stub_ctrl_bytes_q + stub_count_strb(ara_axi_req.w.strb);
          if (stub_data_nonzero(ara_axi_req.w.data, ara_axi_req.w.strb)) begin
            stub_core_release_q <= 1'b1;
            $display("[%t] XDMA-STUB core-release write observed at AXI addr window %h data=%h strb=%h",
                     $realtime, stub_aw_addr_q[stub_aw_rptr_q], ara_axi_req.w.data, ara_axi_req.w.strb);
          end
        end

        if (ara_axi_req.w.last) begin
          stub_b_valid_q  <= 1'b1;
          stub_b_id_q     <= stub_aw_id_q[stub_aw_rptr_q];
          stub_aw_rptr_q  <= stub_aw_rptr_q + 4'd1;
          stub_aw_count_q <= stub_aw_count_q - 5'd1;
          $display("[%t] XDMA-STUB WLAST addr=%h l2_bytes=%0d ctrl_bytes=%0d",
                   $realtime, stub_aw_addr_q[stub_aw_rptr_q], stub_l2_bytes_q, stub_ctrl_bytes_q);
        end
      end
    end
  end
`else
  ara_soc #(
    .NrLanes(NrLanes),
    .NrClusters(NrClusters),
    .AxiDataWidth(AxiDataWidth),
    .AxiAddrWidth(AxiAddrWidth),
    .AxiIdWidth(5),
    .FPUSupport(ara_pkg::FPUSupportNone),
    .FPExtSupport(ara_pkg::FPExtSupportDisable),
    .FixPtSupport(ara_pkg::FixedPointDisable),
    .L2NumWords(2**14),
    .ExternalAxiMaster(1'b1)
  ) i_ara_soc (
    .clk_i(axi_aclk),
`ifdef ARA_HOLD_RESET
    .rst_ni(1'b0),  // DIAGNOSTIC: hold Ara in reset to isolate the link-up storm
`else
    .rst_ni(axi_aresetn),
`endif
    .exit_o(exit_o),
    .hw_cnt_en_o(hw_cnt_en_o),
    .scan_enable_i(1'b0),
    .scan_data_i(1'b0),
    .scan_data_o(),
    .uart_penable_o(uart_penable),
    .uart_pwrite_o(uart_pwrite),
    .uart_paddr_o(uart_paddr),
    .uart_psel_o(uart_psel),
    .uart_pwdata_o(uart_pwdata),
    .uart_prdata_i('0),
    .uart_pready_i(1'b1),
    .uart_pslverr_i(1'b0),
    .ext_axi_awid_i(ara_axi_req.aw.id),
    .ext_axi_awaddr_i(ara_axi_req.aw.addr),
    .ext_axi_awlen_i(ara_axi_req.aw.len),
    .ext_axi_awsize_i(ara_axi_req.aw.size),
    .ext_axi_awburst_i(ara_axi_req.aw.burst),
    .ext_axi_awlock_i(ara_axi_req.aw.lock),
    .ext_axi_awcache_i(ara_axi_req.aw.cache),
    .ext_axi_awprot_i(ara_axi_req.aw.prot),
    .ext_axi_awvalid_i(ara_axi_req.aw_valid),
    .ext_axi_awready_o(ara_axi_resp.aw_ready),
    .ext_axi_wdata_i(ara_axi_req.w.data),
    .ext_axi_wstrb_i(ara_axi_req.w.strb),
    .ext_axi_wlast_i(ara_axi_req.w.last),
    .ext_axi_wvalid_i(ara_axi_req.w_valid),
    .ext_axi_wready_o(ara_axi_resp.w_ready),
    .ext_axi_bid_o(ara_axi_resp.b.id),
    .ext_axi_bresp_o(ara_axi_resp.b.resp),
    .ext_axi_bvalid_o(ara_axi_resp.b_valid),
    .ext_axi_bready_i(ara_axi_req.b_ready),
    .ext_axi_arid_i(ara_axi_req.ar.id),
    .ext_axi_araddr_i(ara_axi_req.ar.addr),
    .ext_axi_arlen_i(ara_axi_req.ar.len),
    .ext_axi_arsize_i(ara_axi_req.ar.size),
    .ext_axi_arburst_i(ara_axi_req.ar.burst),
    .ext_axi_arlock_i(ara_axi_req.ar.lock),
    .ext_axi_arcache_i(ara_axi_req.ar.cache),
    .ext_axi_arprot_i(ara_axi_req.ar.prot),
    .ext_axi_arvalid_i(ara_axi_req.ar_valid),
    .ext_axi_arready_o(ara_axi_resp.ar_ready),
    .ext_axi_rid_o(ara_axi_resp.r.id),
    .ext_axi_rdata_o(ara_axi_resp.r.data),
    .ext_axi_rresp_o(ara_axi_resp.r.resp),
    .ext_axi_rlast_o(ara_axi_resp.r.last),
    .ext_axi_rvalid_o(ara_axi_resp.r_valid),
    .ext_axi_rready_i(ara_axi_req.r_ready)
  );
`endif

  if (XdmaAxiDataWidth != 64) begin : gen_bad_xdma_axi_width
    initial $error("litefury_araxl_xdma_top expects the generated XDMA AXI data width to be 64 bits.");
  end

  if (AxiDataWidth < XdmaAxiDataWidth) begin : gen_bad_ara_axi_width
    initial $error("litefury_araxl_xdma_top only supports XDMA-to-Ara AXI upsizing or equal widths.");
  end

endmodule
