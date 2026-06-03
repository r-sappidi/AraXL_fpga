// AraXL XDMA xsim testbench board, 7-series (GTPE2) variant.
//
// The LiteFury XDMA endpoint is an Artix-7 part, so its PCIe block uses GTPE2
// transceivers. The original board paired it with an UltraScale (GTHE3)
// pcie3_uscale_rp BFM, which cannot train against GTPE2 at the serial level
// (endpoint LTSSM stayed 'zz', causing an X-propagation event storm / OOM).
// This board drives the same XDMA endpoint with a matching 7-series GTPE2 root
// port (xilinx_pcie_2_1_rport_7x), harvested from a pcie_7x example design.
`timescale 1ps/1ps

`include "board_common.vh"

`define SIMULATION

module board;
  parameter REF_CLK_FREQ = 0;

  localparam C_DATA_WIDTH = 64;

  localparam REF_CLK_HALF_CYCLE = (REF_CLK_FREQ == 0) ? 5000 :
                                  (REF_CLK_FREQ == 1) ? 4000 :
                                  (REF_CLK_FREQ == 2) ? 2000 : 0;

`ifdef LINKWIDTH
  localparam [4:0] EP_LINK_WIDTH = 5'd`LINKWIDTH;
`else
  localparam [4:0] EP_LINK_WIDTH = 5'd4;
`endif

  reg sys_rst_n;

  wire ep_sys_clk_p;
  wire ep_sys_clk_n;
  wire ep_sys_clk;
  wire rp_sys_clk;

  wire [(EP_LINK_WIDTH-1):0] ep_pci_exp_txn;
  wire [(EP_LINK_WIDTH-1):0] ep_pci_exp_txp;
  wire [(EP_LINK_WIDTH-1):0] rp_pci_exp_txn;
  wire [(EP_LINK_WIDTH-1):0] rp_pci_exp_txp;

  wire user_lnk_up;
  wire pcie_clkreq_l;
  wire [7:0] c2h_sts_0;
  wire [7:0] h2c_sts_0;
  wire [63:0] exit_o;
  wire [63:0] hw_cnt_en_o;

  // RP reference clock (single-ended for the 7-series root port).
  sys_clk_gen #(
    .halfcycle(REF_CLK_HALF_CYCLE),
    .offset(0)
  ) CLK_GEN_RP (
    .sys_clk(rp_sys_clk)
  );

  // EP reference clock (differential, buffered through the GT clock buffer).
  sys_clk_gen_ds #(
    .halfcycle(REF_CLK_HALF_CYCLE),
    .offset(0)
  ) CLK_GEN_EP (
    .sys_clk_p(ep_sys_clk_p),
    .sys_clk_n(ep_sys_clk_n)
  );

  IBUFDS_GTE2 EP_REFCLK_IBUF (
    .O(ep_sys_clk),
    .ODIV2(),
    .I(ep_sys_clk_p),
    .CEB(1'b0),
    .IB(ep_sys_clk_n)
  );

  litefury_araxl_xdma_top #(
    .NrLanes(`NR_LANES),
    .NrClusters(`NR_CLUSTERS)
  ) EP (
    .sys_clk(ep_sys_clk),
    .sys_rst_n(sys_rst_n),
    .user_lnk_up(user_lnk_up),
    .pci_exp_txp(ep_pci_exp_txp),
    .pci_exp_txn(ep_pci_exp_txn),
    .pci_exp_rxp(rp_pci_exp_txp),
    .pci_exp_rxn(rp_pci_exp_txn),
    .pcie_clkreq_l(pcie_clkreq_l),
    .c2h_sts_0(c2h_sts_0),
    .h2c_sts_0(h2c_sts_0),
    .exit_o(exit_o),
    .hw_cnt_en_o(hw_cnt_en_o)
  );

  xilinx_pcie_2_1_rport_7x #(
    .REF_CLK_FREQ(REF_CLK_FREQ),
    .PL_FAST_TRAIN("TRUE"),
    .ALLOW_X8_GEN2("FALSE"),
    .C_DATA_WIDTH(C_DATA_WIDTH),
    .LINK_CAP_MAX_LINK_WIDTH({1'b0, EP_LINK_WIDTH}),
    .DEVICE_ID(16'h7100),
    .LINK_CAP_MAX_LINK_SPEED(4'h1),
    .LINK_CTRL2_TARGET_LINK_SPEED(4'h1),
    .DEV_CAP_MAX_PAYLOAD_SUPPORTED(2),
    .TRN_DW("FALSE"),
    .VC0_TX_LASTPACKET(29),
    .VC0_RX_RAM_LIMIT(13'h7FF),
    .VC0_CPL_INFINITE("TRUE"),
    .VC0_TOTAL_CREDITS_PD(437),
    .VC0_TOTAL_CREDITS_CD(461),
    .USER_CLK_FREQ(2),
    .USER_CLK2_DIV2("FALSE")
  ) RP (
    .sys_clk(rp_sys_clk),
    .sys_rst_n(sys_rst_n),
    .pci_exp_txn(rp_pci_exp_txn),
    .pci_exp_txp(rp_pci_exp_txp),
    .pci_exp_rxn(ep_pci_exp_txn),
    .pci_exp_rxp(ep_pci_exp_txp)
  );

  integer i;
  initial begin
    $display("[%t] : System Reset Is Asserted...", $realtime);
    sys_rst_n = 1'b0;
    for (i = 0; i < 500; i = i + 1) begin
      @(posedge ep_sys_clk);
    end
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

  // Link-up watchdog: the endpoint must reach L0 (user_lnk_up) or we bail out.
  // The 7-series root port has no user_lnk_up port, so we key off the EP.
  reg last_ep_lnk_up;
  integer link_timeout_cycles;
  initial begin
    last_ep_lnk_up = 1'bx;
    link_timeout_cycles = 0;
    wait (sys_rst_n === 1'b1);
    while (user_lnk_up !== 1'b1 && link_timeout_cycles < 200000) begin
      @(posedge rp_sys_clk);
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

  initial begin
    if ($test$plusargs("dump_all")) begin
      $dumpfile("board.vcd");
      $dumpvars(0, board);
    end
  end
endmodule
