`timescale 1ps/1ps

`include "board_common.vh"

`define SIMULATION

module board;
  parameter REF_CLK_FREQ = 0;

  localparam C_DATA_WIDTH = 64;

  localparam REF_CLK_HALF_CYCLE = (REF_CLK_FREQ == 0) ? 5000 :
                                  (REF_CLK_FREQ == 1) ? 4000 :
                                  (REF_CLK_FREQ == 2) ? 2000 : 0;
  localparam [2:0] PF0_DEV_CAP_MAX_PAYLOAD_SIZE = 3'b010;
  localparam [2:0] RP_LINK_SPEED = 3'h1;

`ifdef LINKWIDTH
  localparam [4:0] EP_LINK_WIDTH = 5'd`LINKWIDTH;
`else
  localparam [4:0] EP_LINK_WIDTH = 5'd4;
`endif

  reg sys_rst_n;

  wire ep_sys_clk_p;
  wire ep_sys_clk_n;
  wire ep_sys_clk;
  wire rp_sys_clk_p;
  wire rp_sys_clk_n;

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

  sys_clk_gen_ds #(
    .halfcycle(REF_CLK_HALF_CYCLE),
    .offset(0)
  ) CLK_GEN_RP (
    .sys_clk_p(rp_sys_clk_p),
    .sys_clk_n(rp_sys_clk_n)
  );

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

  initial begin
    $display("[%t] : System Reset Is Asserted...", $realtime);
    sys_rst_n = 1'b0;
    repeat (500) @(posedge rp_sys_clk_p);
    $display("[%t] : System Reset Is De-asserted...", $realtime);
    sys_rst_n = 1'b1;
  end

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

  xilinx_pcie3_uscale_rp #(
    .PL_LINK_CAP_MAX_LINK_SPEED(RP_LINK_SPEED),
    .PL_LINK_CAP_MAX_LINK_WIDTH(EP_LINK_WIDTH[3:0]),
    .PF0_DEV_CAP_MAX_PAYLOAD_SIZE(PF0_DEV_CAP_MAX_PAYLOAD_SIZE)
  ) RP (
    .sys_clk_n(rp_sys_clk_n),
    .sys_clk_p(rp_sys_clk_p),
    .sys_rst_n(sys_rst_n),
    .pci_exp_txn(rp_pci_exp_txn),
    .pci_exp_txp(rp_pci_exp_txp),
    .pci_exp_rxn(ep_pci_exp_txn),
    .pci_exp_rxp(ep_pci_exp_txp)
  );

  always @(posedge EP.axi_aclk) begin
    if (EP.axi_aresetn && exit_o[0]) begin
      $display("[%t] : Ara exit register written: %h", $realtime, exit_o);
      $finish;
    end
  end

  reg [5:0] last_rp_ltssm;
  reg [5:0] last_ep_ltssm;
  reg last_rp_lnk_up;
  reg last_ep_lnk_up;
  reg last_rp_user_reset;
  integer link_timeout_cycles;

  initial begin
    last_rp_ltssm = 6'h3f;
    last_ep_ltssm = 6'h3f;
    last_rp_lnk_up = 1'bx;
    last_ep_lnk_up = 1'bx;
    last_rp_user_reset = 1'bx;
    link_timeout_cycles = 0;
    wait (sys_rst_n === 1'b1);
    while ((user_lnk_up !== 1'b1 || RP.pcie3_uscale_rp_top_i.user_lnk_up !== 1'b1) &&
           link_timeout_cycles < 100000) begin
      @(posedge rp_sys_clk_p);
      link_timeout_cycles = link_timeout_cycles + 1;
    end
    if (user_lnk_up !== 1'b1 || RP.pcie3_uscale_rp_top_i.user_lnk_up !== 1'b1) begin
      $display("[%t] : ERROR: PCIe link-up timeout", $realtime);
      $display("[%t] :   EP user_lnk_up=%b ltssm=0x%02h phy_link_status=%b negotiated_width=0x%0h current_speed=0x%0h",
               $realtime,
               user_lnk_up,
               EP.i_xdma.inst.xdma_1_pcie2_to_pcie3_wrapper_i.cfg_ltssm_state,
               EP.i_xdma.inst.xdma_1_pcie2_to_pcie3_wrapper_i.cfg_phy_link_status,
               EP.i_xdma.inst.xdma_1_pcie2_to_pcie3_wrapper_i.cfg_negotiated_width,
               EP.i_xdma.inst.xdma_1_pcie2_to_pcie3_wrapper_i.cfg_current_speed);
      $display("[%t] :   RP user_lnk_up=%b user_reset=%b ltssm=0x%02h phy_link_status=%b negotiated_width=0x%0h current_speed=0x%0h",
               $realtime,
               RP.pcie3_uscale_rp_top_i.user_lnk_up,
               RP.pcie3_uscale_rp_top_i.user_reset,
               RP.pcie3_uscale_rp_top_i.cfg_ltssm_state,
               RP.pcie3_uscale_rp_top_i.cfg_phy_link_status,
               RP.pcie3_uscale_rp_top_i.cfg_negotiated_width,
               RP.pcie3_uscale_rp_top_i.cfg_current_speed);
      $fatal(1, "PCIe link did not train");
    end
  end

  always @(posedge rp_sys_clk_p) begin
    if (RP.pcie3_uscale_rp_top_i.cfg_ltssm_state !== last_rp_ltssm ||
        EP.i_xdma.inst.xdma_1_pcie2_to_pcie3_wrapper_i.cfg_ltssm_state !== last_ep_ltssm ||
        RP.pcie3_uscale_rp_top_i.user_lnk_up !== last_rp_lnk_up ||
        user_lnk_up !== last_ep_lnk_up ||
        RP.pcie3_uscale_rp_top_i.user_reset !== last_rp_user_reset) begin
      $display("[%t] : PCIe status: ep_lnk=%b ep_ltssm=0x%02h ep_phy=%b rp_lnk=%b rp_reset=%b rp_ltssm=0x%02h rp_phy=%b",
               $realtime,
               user_lnk_up,
               EP.i_xdma.inst.xdma_1_pcie2_to_pcie3_wrapper_i.cfg_ltssm_state,
               EP.i_xdma.inst.xdma_1_pcie2_to_pcie3_wrapper_i.cfg_phy_link_status,
               RP.pcie3_uscale_rp_top_i.user_lnk_up,
               RP.pcie3_uscale_rp_top_i.user_reset,
               RP.pcie3_uscale_rp_top_i.cfg_ltssm_state,
               RP.pcie3_uscale_rp_top_i.cfg_phy_link_status);
      last_rp_ltssm <= RP.pcie3_uscale_rp_top_i.cfg_ltssm_state;
      last_ep_ltssm <= EP.i_xdma.inst.xdma_1_pcie2_to_pcie3_wrapper_i.cfg_ltssm_state;
      last_rp_lnk_up <= RP.pcie3_uscale_rp_top_i.user_lnk_up;
      last_ep_lnk_up <= user_lnk_up;
      last_rp_user_reset <= RP.pcie3_uscale_rp_top_i.user_reset;
    end
  end

  initial begin
    if ($test$plusargs("dump_all")) begin
      $dumpfile("board.vcd");
      $dumpvars(0, board);
    end
  end
endmodule
