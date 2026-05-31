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
    parameter int unsigned AxiAddrWidth = 64,
    parameter int unsigned AxiSocIdWidth = 4
  ) (
    input  logic       sys_clk,
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
  );

  logic axi_aclk;
  logic axi_aresetn;
  logic msi_enable;
  logic [2:0] msi_vector_width;
  logic [0:0] usr_irq_req;
  logic [0:0] usr_irq_ack;

  assign usr_irq_req = '0;
  assign pcie_clkreq_l = 1'b0;

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
  logic [AxiDataWidth-1:0]   m_axi_wdata;
  logic [AxiDataWidth/8-1:0] m_axi_wstrb;
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
  logic [AxiDataWidth-1:0]   m_axi_rdata;
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
  );

  ara_soc #(
    .NrLanes(NrLanes),
    .NrClusters(NrClusters),
    .AxiAddrWidth(AxiAddrWidth),
    .AxiIdWidth(5),
    .FPUSupport(ara_pkg::FPUSupportNone),
    .FPExtSupport(ara_pkg::FPExtSupportDisable),
    .FixPtSupport(ara_pkg::FixedPointDisable),
    .L2NumWords(2**14),
    .ExternalAxiMaster(1'b1)
  ) i_ara_soc (
    .clk_i(axi_aclk),
    .rst_ni(axi_aresetn),
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
    .ext_axi_awid_i(m_axi_awid),
    .ext_axi_awaddr_i(m_axi_awaddr),
    .ext_axi_awlen_i(m_axi_awlen),
    .ext_axi_awsize_i(m_axi_awsize),
    .ext_axi_awburst_i(m_axi_awburst),
    .ext_axi_awlock_i(m_axi_awlock),
    .ext_axi_awcache_i(m_axi_awcache),
    .ext_axi_awprot_i(m_axi_awprot),
    .ext_axi_awvalid_i(m_axi_awvalid),
    .ext_axi_awready_o(m_axi_awready),
    .ext_axi_wdata_i(m_axi_wdata),
    .ext_axi_wstrb_i(m_axi_wstrb),
    .ext_axi_wlast_i(m_axi_wlast),
    .ext_axi_wvalid_i(m_axi_wvalid),
    .ext_axi_wready_o(m_axi_wready),
    .ext_axi_bid_o(m_axi_bid),
    .ext_axi_bresp_o(m_axi_bresp),
    .ext_axi_bvalid_o(m_axi_bvalid),
    .ext_axi_bready_i(m_axi_bready),
    .ext_axi_arid_i(m_axi_arid),
    .ext_axi_araddr_i(m_axi_araddr),
    .ext_axi_arlen_i(m_axi_arlen),
    .ext_axi_arsize_i(m_axi_arsize),
    .ext_axi_arburst_i(m_axi_arburst),
    .ext_axi_arlock_i(m_axi_arlock),
    .ext_axi_arcache_i(m_axi_arcache),
    .ext_axi_arprot_i(m_axi_arprot),
    .ext_axi_arvalid_i(m_axi_arvalid),
    .ext_axi_arready_o(m_axi_arready),
    .ext_axi_rid_o(m_axi_rid),
    .ext_axi_rdata_o(m_axi_rdata),
    .ext_axi_rresp_o(m_axi_rresp),
    .ext_axi_rlast_o(m_axi_rlast),
    .ext_axi_rvalid_o(m_axi_rvalid),
    .ext_axi_rready_i(m_axi_rready)
  );

  if (AxiDataWidth != 64) begin : gen_bad_axi_width
    initial $error("litefury_araxl_xdma_top requires 64-bit AraXL AXI; use NR_LANES*NR_CLUSTERS=2.");
  end

endmodule
