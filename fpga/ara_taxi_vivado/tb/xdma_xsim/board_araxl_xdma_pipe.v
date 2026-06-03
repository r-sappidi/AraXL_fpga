// AraXL XDMA xsim testbench board, PIPE-mode variant.
//
// The Artix-7 XDMA endpoint (GTPE2) cannot serially train against the UltraScale
// (GTHE3) root-port BFM, and even a matched-GTPE2 serial pair storms in xsim.
// PIPE mode sidesteps the transceivers entirely: EXT_PIPE_SIM disconnects the
// GTs on both the endpoint and the root port, and we cross-wire their parallel
// PIPE buses (common_commands + pipe_tx/rx_*_sigs) directly. The XDMA's own
// example root port (pcie3_uscale_rp) is the matched PIPE partner (26b common /
// 84b lane), and its BFM provides the TSK_XDMA_REG_* tasks the stimulus uses.
//
// Interconnect mirrors the pristine XDMA pcie example board.v PIPE template.
`timescale 1ps/1ps

`include "board_common.vh"

`define SIMULATION

module board;
  parameter REF_CLK_FREQ = 0;

  // The XDMA root-port BFM (pci_exp_usrapp_tx.v) reads board.C_DATA_WIDTH to
  // size its AXI peek into the endpoint (board.EP.m_axi_wdata/wstrb). The XDMA
  // AXI data width is 64.
  localparam C_DATA_WIDTH = 64;

  localparam REF_CLK_HALF_CYCLE = (REF_CLK_FREQ == 0) ? 5000 :
                                  (REF_CLK_FREQ == 1) ? 4000 :
                                  (REF_CLK_FREQ == 2) ? 2000 : 0;
  localparam [2:0] PF0_DEV_CAP_MAX_PAYLOAD_SIZE = 3'b010;

  // Force PIPE-mode (GT-less) simulation on both cores.
  localparam EXT_PIPE_SIM = "TRUE";
  defparam board.EP.i_xdma.inst.xdma_1_pcie2_to_pcie3_wrapper_i.pcie2_ip_i.inst.inst.EXT_PIPE_SIM = "TRUE";
  defparam board.RP.pcie3_uscale_rp_top_i.pcie3_uscale_core_top_inst.EXT_PIPE_SIM = "TRUE";

  integer i;
  reg sys_rst_n;

  wire ep_sys_clk;
  wire ep_sys_clk_p;
  wire ep_sys_clk_n;
  wire rp_sys_clk_p;
  wire rp_sys_clk_n;

  wire user_lnk_up;
  wire pcie_clkreq_l;
  wire [7:0] c2h_sts_0;
  wire [7:0] h2c_sts_0;
  wire [63:0] exit_o;
  wire [63:0] hw_cnt_en_o;

  // Xilinx PIPE interface buses (84b/lane, 26b common; [0] of common is pipe_clk).
  wire [25:0] common_commands_out;
  wire [83:0] xil_tx0_sigs_ep, xil_tx1_sigs_ep, xil_tx2_sigs_ep, xil_tx3_sigs_ep;
  wire [83:0] xil_tx4_sigs_ep, xil_tx5_sigs_ep, xil_tx6_sigs_ep, xil_tx7_sigs_ep;
  wire [83:0] xil_rx0_sigs_ep, xil_rx1_sigs_ep, xil_rx2_sigs_ep, xil_rx3_sigs_ep;
  wire [83:0] xil_rx4_sigs_ep, xil_rx5_sigs_ep, xil_rx6_sigs_ep, xil_rx7_sigs_ep;
  wire [83:0] xil_tx0_sigs_rp, xil_tx1_sigs_rp, xil_tx2_sigs_rp, xil_tx3_sigs_rp;
  wire [83:0] xil_tx4_sigs_rp, xil_tx5_sigs_rp, xil_tx6_sigs_rp, xil_tx7_sigs_rp;

  // Reference clocks (unused for the link in PIPE mode, but cores still need them).
  sys_clk_gen_ds #(.halfcycle(REF_CLK_HALF_CYCLE), .offset(0))
    CLK_GEN_RP (.sys_clk_p(rp_sys_clk_p), .sys_clk_n(rp_sys_clk_n));
  sys_clk_gen_ds #(.halfcycle(REF_CLK_HALF_CYCLE), .offset(0))
    CLK_GEN_EP (.sys_clk_p(ep_sys_clk_p), .sys_clk_n(ep_sys_clk_n));
  IBUFDS_GTE2 EP_REFCLK_IBUF (.O(ep_sys_clk), .ODIV2(), .I(ep_sys_clk_p), .CEB(1'b0), .IB(ep_sys_clk_n));

  // Endpoint: AraXL XDMA top. Serial PCIe pins are unused in PIPE mode.
  litefury_araxl_xdma_top #(
    .NrLanes(`NR_LANES),
    .NrClusters(`NR_CLUSTERS)
  ) EP (
    .sys_clk(ep_sys_clk),
    .sys_rst_n(sys_rst_n),
    .user_lnk_up(user_lnk_up),
    .pci_exp_txp(), .pci_exp_txn(),
    .pci_exp_rxp(4'b0), .pci_exp_rxn(4'b0),
    .pcie_clkreq_l(pcie_clkreq_l),
    .c2h_sts_0(c2h_sts_0),
    .h2c_sts_0(h2c_sts_0),
    .exit_o(exit_o),
    .hw_cnt_en_o(hw_cnt_en_o),
    // PIPE interface
    .common_commands_in(26'b0),
    .pipe_rx_0_sigs(xil_rx0_sigs_ep),
    .pipe_rx_1_sigs(xil_rx1_sigs_ep),
    .pipe_rx_2_sigs(xil_rx2_sigs_ep),
    .pipe_rx_3_sigs(xil_rx3_sigs_ep),
    .pipe_rx_4_sigs(xil_rx4_sigs_ep),
    .pipe_rx_5_sigs(xil_rx5_sigs_ep),
    .pipe_rx_6_sigs(xil_rx6_sigs_ep),
    .pipe_rx_7_sigs(xil_rx7_sigs_ep),
    .common_commands_out(common_commands_out),
    .pipe_tx_0_sigs(xil_tx0_sigs_ep),
    .pipe_tx_1_sigs(xil_tx1_sigs_ep),
    .pipe_tx_2_sigs(xil_tx2_sigs_ep),
    .pipe_tx_3_sigs(xil_tx3_sigs_ep),
    .pipe_tx_4_sigs(xil_tx4_sigs_ep),
    .pipe_tx_5_sigs(xil_tx5_sigs_ep),
    .pipe_tx_6_sigs(xil_tx6_sigs_ep),
    .pipe_tx_7_sigs(xil_tx7_sigs_ep)
  );

  // Root port BFM (the XDMA's matched companion), driven over PIPE.
  xilinx_pcie3_uscale_rp #(
    .PF0_DEV_CAP_MAX_PAYLOAD_SIZE(PF0_DEV_CAP_MAX_PAYLOAD_SIZE)
  ) RP (
    .sys_clk_n(rp_sys_clk_n),
    .sys_clk_p(rp_sys_clk_p),
    .sys_rst_n(sys_rst_n),
    .common_commands_in({25'b0, common_commands_out[0]}), // pipe_clk from EP
    .pipe_rx_0_sigs({45'b0, xil_tx0_sigs_ep[38:0]}),
    .pipe_rx_1_sigs({45'b0, xil_tx1_sigs_ep[38:0]}),
    .pipe_rx_2_sigs({45'b0, xil_tx2_sigs_ep[38:0]}),
    .pipe_rx_3_sigs({45'b0, xil_tx3_sigs_ep[38:0]}),
    .pipe_rx_4_sigs({45'b0, xil_tx4_sigs_ep[38:0]}),
    .pipe_rx_5_sigs({45'b0, xil_tx5_sigs_ep[38:0]}),
    .pipe_rx_6_sigs({45'b0, xil_tx6_sigs_ep[38:0]}),
    .pipe_rx_7_sigs({45'b0, xil_tx7_sigs_ep[38:0]}),
    .common_commands_out(),
    .pipe_tx_0_sigs(xil_tx0_sigs_rp),
    .pipe_tx_1_sigs(xil_tx1_sigs_rp),
    .pipe_tx_2_sigs(xil_tx2_sigs_rp),
    .pipe_tx_3_sigs(xil_tx3_sigs_rp),
    .pipe_tx_4_sigs(xil_tx4_sigs_rp),
    .pipe_tx_5_sigs(xil_tx5_sigs_rp),
    .pipe_tx_6_sigs(xil_tx6_sigs_rp),
    .pipe_tx_7_sigs(xil_tx7_sigs_rp)
  );

  // RP TX -> EP RX (low 39 bits per lane carry the PIPE data for Gen1).
  assign xil_rx0_sigs_ep = {45'b0, xil_tx0_sigs_rp[38:0]};
  assign xil_rx1_sigs_ep = {45'b0, xil_tx1_sigs_rp[38:0]};
  assign xil_rx2_sigs_ep = {45'b0, xil_tx2_sigs_rp[38:0]};
  assign xil_rx3_sigs_ep = {45'b0, xil_tx3_sigs_rp[38:0]};
  assign xil_rx4_sigs_ep = {45'b0, xil_tx4_sigs_rp[38:0]};
  assign xil_rx5_sigs_ep = {45'b0, xil_tx5_sigs_rp[38:0]};
  assign xil_rx6_sigs_ep = {45'b0, xil_tx6_sigs_rp[38:0]};
  assign xil_rx7_sigs_ep = {45'b0, xil_tx7_sigs_rp[38:0]};

  initial begin
    $display("[%t] : System Reset Is Asserted...", $realtime);
    sys_rst_n = 1'b0;
    repeat (500) @(posedge rp_sys_clk_p);
    $display("[%t] : System Reset Is De-asserted...", $realtime);
    sys_rst_n = 1'b1;
  end

  // Finish when the program writes the Ara exit register.
  always @(posedge EP.axi_aclk) begin
    if (EP.axi_aresetn && exit_o[0]) begin
      $display("[%t] : Ara exit register written: %h", $realtime, exit_o);
      $finish;
    end
  end

  // Link-up watchdog (PIPE mode trains quickly).
  reg last_ep_lnk_up;
  integer link_timeout_cycles;
  initial begin
    last_ep_lnk_up = 1'bx;
    link_timeout_cycles = 0;
    wait (sys_rst_n === 1'b1);
    while (user_lnk_up !== 1'b1 && link_timeout_cycles < 200000) begin
      @(posedge rp_sys_clk_p);
      link_timeout_cycles = link_timeout_cycles + 1;
      if (user_lnk_up !== last_ep_lnk_up) begin
        $display("[%t] : PCIe EP user_lnk_up=%b", $realtime, user_lnk_up);
        last_ep_lnk_up = user_lnk_up;
      end
    end
    if (user_lnk_up !== 1'b1) begin
      $display("[%t] : ERROR: PCIe link-up timeout (EP user_lnk_up=%b)", $realtime, user_lnk_up);
      $fatal(1, "PCIe link did not train");
    end
    $display("[%t] : PCIe link is up (EP user_lnk_up=1)", $realtime);
  end

  // Activity counters (edge-sampled, so no clock aliasing): prove the PIPE clock
  // and PIPE data buses are actually toggling.
  integer pclk_edges = 0;
  integer ep_tx_edges = 0;
  integer rp_tx_edges = 0;
  integer aclk_edges = 0;
  always @(common_commands_out[0]) pclk_edges = pclk_edges + 1;
  always @(xil_tx0_sigs_ep) ep_tx_edges = ep_tx_edges + 1;
  always @(xil_tx0_sigs_rp) rp_tx_edges = rp_tx_edges + 1;
  always @(posedge EP.axi_aclk) aclk_edges = aclk_edges + 1;

  // XDMA AXI master (m_axi) handshake counters: shows if the H2C DMA is issuing
  // writes to Ara's L2 and whether Ara accepts/responds.
  integer m_awh=0, m_wh=0, m_bh=0, m_arh=0, m_rh=0;
  // Ara-side (post dw_converter, 256-bit) handshake counters.
  integer a_awh=0, a_wh=0, a_bh=0;
  always @(posedge EP.axi_aclk) begin
    if (EP.m_axi_awvalid===1'b1 && EP.m_axi_awready===1'b1) m_awh = m_awh + 1;
    if (EP.m_axi_wvalid ===1'b1 && EP.m_axi_wready ===1'b1) m_wh  = m_wh  + 1;
    if (EP.m_axi_bvalid ===1'b1 && EP.m_axi_bready ===1'b1) m_bh  = m_bh  + 1;
    if (EP.m_axi_arvalid===1'b1 && EP.m_axi_arready===1'b1) m_arh = m_arh + 1;
    if (EP.m_axi_rvalid ===1'b1 && EP.m_axi_rready ===1'b1) m_rh  = m_rh  + 1;
    if (EP.ara_axi_req.aw_valid===1'b1 && EP.ara_axi_resp.aw_ready===1'b1) a_awh = a_awh + 1;
    if (EP.ara_axi_req.w_valid ===1'b1 && EP.ara_axi_resp.w_ready ===1'b1) a_wh  = a_wh  + 1;
    if (EP.ara_axi_resp.b_valid===1'b1 && EP.ara_axi_req.b_ready ===1'b1) a_bh  = a_bh  + 1;
  end

  // One-shot probe: is the gated CVA6 master (xbar slave port 0) presenting X
  // to the shared xbar while the ext (XDMA) master's write stalls?
  reg cva6_probed = 1'b0;
  always @(posedge EP.axi_aclk) if (armed && !cva6_probed && EP.ara_axi_req.aw_valid===1'b1) begin
    cva6_probed <= 1'b1;
    $display("[%t] CVA6-MST(sysport0): awv=%b arv=%b wv=%b bready=%b | sys_rstn=%b",
             $realtime,
             EP.i_ara_soc.system_axi_req[0].aw_valid, EP.i_ara_soc.system_axi_req[0].ar_valid,
             EP.i_ara_soc.system_axi_req[0].w_valid,  EP.i_ara_soc.system_axi_req[0].b_ready,
             EP.i_ara_soc.system_rst_n);
  end

  // Heartbeat: prints every 1 us of SIM time. If these stop appearing while the
  // process is still alive, simulated time has frozen (zero-delay deadlock).
  always begin
    #1000000;
    $display("[HB %t] lnk=%b m_axi[aw=%0d w=%0d b=%0d wrdy=%b] ara[aw=%0d w=%0d b=%0d | awv=%b awr=%b wv=%b wr=%b] xdma_wv=%b xdma_wd=%h exit=%b", $realtime,
             user_lnk_up,
             m_awh, m_wh, m_bh, EP.m_axi_wready,
             a_awh, a_wh, a_bh,
             EP.ara_axi_req.aw_valid, EP.ara_axi_resp.aw_ready, EP.ara_axi_req.w_valid, EP.ara_axi_resp.w_ready,
             EP.m_axi_wvalid, EP.m_axi_wdata, exit_o[0]);
  end

  // Absolute backstop watchdog: guarantees the sim ends even if the program
  // hangs after link-up (sim time still advancing). Link-up itself is gated by
  // the cycle-counted monitor above.
  initial begin
    #2000000000;  // 2 ms
    $display("[%t] WATCHDOG: 2 ms reached without exit (user_lnk_up=%b exit=%b)",
             $realtime, user_lnk_up, exit_o);
    $fatal(1, "WATCHDOG timeout");
  end

  // Catch the AXI reset release (link-up) and the XDMA master's valid lines at
  // that instant -- if they are X, that is the storm source into the Ara AXI path.
  always @(EP.axi_aresetn) begin
    $display("[%t] ARESETN -> %b | m_axi awv=%b arv=%b wv=%b | sysrstn=%b core_rel=%b araq_awv=%b araq_arv=%b araq_wv=%b",
             $realtime, EP.axi_aresetn, EP.m_axi_awvalid, EP.m_axi_arvalid, EP.m_axi_wvalid,
             EP.i_ara_soc.system_rst_n, EP.i_ara_soc.core_release[0],
             EP.ara_axi_req.aw_valid, EP.ara_axi_req.ar_valid, EP.ara_axi_req.w_valid);
  end
  // Sample again shortly after release to catch X that appears post-reset.
  reg armed = 1'b0;
  always @(posedge EP.axi_aresetn) armed <= 1'b1;
  // One-shot dump of the AW attributes the dw_converter presents to Ara.
  reg aw_dumped = 1'b0;
  always @(posedge EP.axi_aclk) begin
    if (EP.ara_axi_req.aw_valid === 1'b1 && !aw_dumped) begin
      aw_dumped <= 1'b1;
      $display("[%t] ARA AW: addr=%h len=%0d size=%0d burst=%0d lock=%b cache=%h prot=%h atop=%h id=%h",
               $realtime, EP.ara_axi_req.aw.addr, EP.ara_axi_req.aw.len, EP.ara_axi_req.aw.size,
               EP.ara_axi_req.aw.burst, EP.ara_axi_req.aw.lock, EP.ara_axi_req.aw.cache,
               EP.ara_axi_req.aw.prot, EP.ara_axi_req.aw.atop, EP.ara_axi_req.aw.id);
    end
  end
  always @(posedge EP.axi_aclk) if (armed) begin
    if ((^{EP.ara_axi_req.aw_valid, EP.ara_axi_req.ar_valid, EP.ara_axi_req.w_valid,
          EP.ara_axi_resp.aw_ready, EP.ara_axi_resp.ar_ready, EP.ara_axi_resp.r_valid}) === 1'bx)
      $display("[%t] POST-RST X on ara AXI: araq_awv=%b arv=%b wv=%b resp_awr=%b arr=%b rv=%b",
               $realtime, EP.ara_axi_req.aw_valid, EP.ara_axi_req.ar_valid, EP.ara_axi_req.w_valid,
               EP.ara_axi_resp.aw_ready, EP.ara_axi_resp.ar_ready, EP.ara_axi_resp.r_valid);
  end

  initial begin
    if ($test$plusargs("dump_all")) begin
      $dumpfile("board.vcd");
      $dumpvars(0, board);
    end
  end
endmodule
