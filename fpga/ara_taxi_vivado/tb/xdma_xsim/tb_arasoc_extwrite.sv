// tb_arasoc_extwrite.sv
// ----------------------------------------------------------------------------
// Standalone ISOLATION testbench for the AraXL ext-AXI -> L2 write path.
//
// Purpose: determine whether the delta-cycle storm seen in the full XDMA flow
// is inherent to the AraXL SoC fabric under xsim, or an artifact of the XDMA
// integration (XDMA IP, PIPE BFM, clock-domain crossing, and the `ifdef XSIM`
// clock-gate / forced-mux hacks in ara_soc).
//
// This TB instantiates ara_soc DIRECTLY and drives its external AXI master port
// with a clean synthetic 512-byte INCR write burst to L2 (0x8000_0000) -- the
// same shape the XDMA H2C engine produces. There is NO XDMA, NO PIPE BFM, and
// NO clock-domain crossing. It is intended to be compiled WITHOUT `XSIM`, so
// none of the ifdef-XSIM hacks are present: the core is held in reset via
// CoreReleaseGate (core_release is never asserted) but clocked normally, so it
// resets cleanly (no unclocked-X), and the SoC clock is ungated.
//
// Outcome interpretation:
//   * Write completes (B response), sim-time keeps advancing  => the AraXL
//     fabric handles an external write cleanly in xsim; the storm is in the
//     XDMA integration, NOT the fabric.
//   * Sim-time freezes / memory balloons (heartbeat stops)     => the fabric
//     ext->L2 write path storms in xsim independent of the XDMA work.
// ----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_arasoc_extwrite;

  localparam int unsigned NrLanes       = `NR_LANES;
  localparam int unsigned NrClusters    = `NR_CLUSTERS;
  localparam int unsigned AxiDataWidth  = 32*NrLanes*NrClusters;
  localparam int unsigned AxiAddrWidth  = 64;
  localparam int unsigned AxiIdWidth    = 5;
  localparam int unsigned AxiSocIdWidth = AxiIdWidth - 1; // NrAXIMasters = 2
  localparam int unsigned StrbWidth     = AxiDataWidth/8;

  logic                      clk, rst_n;

  logic [AxiSocIdWidth-1:0]  awid;
  logic [AxiAddrWidth-1:0]   awaddr;
  logic [7:0]                awlen;
  logic [2:0]                awsize;
  logic [1:0]                awburst;
  logic                      awlock;
  logic [3:0]                awcache;
  logic [2:0]                awprot;
  logic                      awvalid, awready;
  logic [AxiDataWidth-1:0]   wdata;
  logic [StrbWidth-1:0]      wstrb;
  logic                      wlast, wvalid, wready;
  logic [AxiSocIdWidth-1:0]  bid;
  logic [1:0]                bresp;
  logic                      bvalid, bready;
  logic [AxiSocIdWidth-1:0]  arid;
  logic [AxiAddrWidth-1:0]   araddr;
  logic [7:0]                arlen;
  logic [2:0]                arsize;
  logic [1:0]                arburst;
  logic                      arlock;
  logic [3:0]                arcache;
  logic [2:0]                arprot;
  logic                      arvalid, arready;
  logic [AxiSocIdWidth-1:0]  rid;
  logic [AxiDataWidth-1:0]   rdata;
  logic [1:0]                rresp;
  logic                      rlast, rvalid, rready;
  logic [63:0]               exit_o, hw_cnt_en_o;

  ara_soc #(
    .NrLanes          (NrLanes                  ),
    .NrClusters       (NrClusters               ),
    .AxiDataWidth     (AxiDataWidth             ),
    .AxiAddrWidth     (AxiAddrWidth             ),
    .AxiIdWidth       (AxiIdWidth               ),
    .FPUSupport       (ara_pkg::FPUSupportNone  ),
    .FPExtSupport     (ara_pkg::FPExtSupportDisable),
    .FixPtSupport     (ara_pkg::FixedPointDisable),
    .L2NumWords       (2**14                    ),
    .ExternalAxiMaster(1'b1                     ),
    .CoreReleaseGate  (1'b1                     )
  ) i_dut (
    .clk_i            (clk          ),
    .rst_ni           (rst_n        ),
    .exit_o           (exit_o       ),
    .hw_cnt_en_o      (hw_cnt_en_o  ),
    .scan_enable_i    (1'b0         ),
    .scan_data_i      (1'b0         ),
    .scan_data_o      (             ),
    .uart_penable_o   (             ),
    .uart_pwrite_o    (             ),
    .uart_paddr_o     (             ),
    .uart_psel_o      (             ),
    .uart_pwdata_o    (             ),
    .uart_prdata_i    (32'b0        ),
    .uart_pready_i    (1'b1         ),
    .uart_pslverr_i   (1'b0         ),
    .ext_axi_awid_i   (awid         ),
    .ext_axi_awaddr_i (awaddr       ),
    .ext_axi_awlen_i  (awlen        ),
    .ext_axi_awsize_i (awsize       ),
    .ext_axi_awburst_i(awburst      ),
    .ext_axi_awlock_i (awlock       ),
    .ext_axi_awcache_i(awcache      ),
    .ext_axi_awprot_i (awprot       ),
    .ext_axi_awvalid_i(awvalid      ),
    .ext_axi_awready_o(awready      ),
    .ext_axi_wdata_i  (wdata        ),
    .ext_axi_wstrb_i  (wstrb        ),
    .ext_axi_wlast_i  (wlast        ),
    .ext_axi_wvalid_i (wvalid       ),
    .ext_axi_wready_o (wready       ),
    .ext_axi_bid_o    (bid          ),
    .ext_axi_bresp_o  (bresp        ),
    .ext_axi_bvalid_o (bvalid       ),
    .ext_axi_bready_i (bready       ),
    .ext_axi_arid_i   (arid         ),
    .ext_axi_araddr_i (araddr       ),
    .ext_axi_arlen_i  (arlen        ),
    .ext_axi_arsize_i (arsize       ),
    .ext_axi_arburst_i(arburst      ),
    .ext_axi_arlock_i (arlock       ),
    .ext_axi_arcache_i(arcache      ),
    .ext_axi_arprot_i (arprot       ),
    .ext_axi_arvalid_i(arvalid      ),
    .ext_axi_arready_o(arready      ),
    .ext_axi_rid_o    (rid          ),
    .ext_axi_rdata_o  (rdata        ),
    .ext_axi_rresp_o  (rresp        ),
    .ext_axi_rlast_o  (rlast        ),
    .ext_axi_rvalid_o (rvalid       ),
    .ext_axi_rready_i (rready       )
  );

  // 250 MHz clock
  initial clk = 1'b0;
  always #2 clk = ~clk;

  // Heartbeat: proves sim-time advances. If a delta storm freezes time, these
  // stop printing and (because $time never reaches the watchdog) only a memory
  // balloon will show it.
  initial forever begin
    #500;
    $display("[HB t=%0t] awr=%b wr=%b bv=%b", $time, awready, wready, bvalid);
  end

  // Watchdog (only fires if time keeps advancing; a storm won't reach it).
  initial begin
    #100000;
    $display("[TB t=%0t] WATCHDOG: no completion by 100us -> FAIL", $time);
    $finish;
  end

  integer i;
  initial begin
    awid=0; awaddr=0; awlen=0; awsize=0; awburst=0; awlock=0; awcache=0; awprot=0; awvalid=0;
    wdata=0; wstrb=0; wlast=0; wvalid=0; bready=1'b1;
    arid=0; araddr=0; arlen=0; arsize=0; arburst=0; arlock=0; arcache=0; arprot=0; arvalid=0; rready=1'b1;
    rst_n=1'b0;
    repeat (30) @(posedge clk);
    rst_n=1'b1;
    repeat (30) @(posedge clk);
    $display("[TB t=%0t] reset released; core parked via CoreReleaseGate (clocked reset, no XSIM hacks); issuing INCR write burst to 0x8000_0000", $time);

    // ---- AW ----
    @(negedge clk);
    awid=0; awaddr=64'h0000_0000_8000_0000; awlen=8'd15; awsize=3'd5; awburst=2'b01;
    awlock=0; awcache=4'h3; awprot=0; awvalid=1'b1;
    do @(posedge clk); while (!awready);
    @(negedge clk); awvalid=1'b0;
    $display("[TB t=%0t] AW accepted", $time);

    // ---- W beats (16 x 256-bit) ----
    for (i=0; i<16; i=i+1) begin
      @(negedge clk);
      wdata = {{(AxiDataWidth-32){1'b0}}, 32'hA5A5_0000} | i;
      wstrb = {StrbWidth{1'b1}};
      wlast = (i==15);
      wvalid= 1'b1;
      do @(posedge clk); while (!wready);
      $display("[TB t=%0t] W beat %0d accepted (wlast=%b)", $time, i, wlast);
    end
    @(negedge clk); wvalid=1'b0; wlast=1'b0;

    // ---- B ----
    do @(posedge clk); while (!bvalid);
    $display("[TB t=%0t] *** B RESPONSE resp=%0d id=%0d => WRITE COMPLETED, NO STORM ***", $time, bresp, bid);
    repeat (20) @(posedge clk);
    $display("[TB t=%0t] DONE", $time);
    $finish;
  end

endmodule
