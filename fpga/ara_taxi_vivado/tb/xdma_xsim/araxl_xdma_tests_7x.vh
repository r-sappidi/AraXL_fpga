// AraXL stimulus for the 7-series (GTPE2) root-port BFM.
//
// This is included inside pci_exp_usrapp_tx.v's testname dispatch chain, so it
// must be a sequence of `else if (testname == ...)` clauses. The body runs as
// BFM task calls (raw PCIe TLPs) against the XDMA endpoint.
//
// STEP 3 milestone: prove the GTPE2<->GTPE2 link trains against the XDMA EP.
// TSK_SYSTEM_INITIALIZATION waits for transaction reset to de-assert and the
// link to reach L0; the board's user_lnk_up monitor then confirms it. The full
// payload-load + core-release sequence (raw TLPs replacing the old XDMA-example
// TSK_XDMA_REG_* helpers) is step 4.
else if (testname == "araxl_dotproduct")
begin : araxl_dotproduct_test
  TSK_SYSTEM_INITIALIZATION;
  $display("[%t] [ARAXL] TSK_SYSTEM_INITIALIZATION complete (link trained).", $realtime);
  TSK_BAR_INIT;
  $display("[%t] [ARAXL] TSK_BAR_INIT complete (endpoint BARs enumerated).", $realtime);
  // Idle briefly so the board-level link-up monitor can observe user_lnk_up.
  TSK_TX_CLK_EAT(2000);
  $display("[%t] [ARAXL] link-up validation milestone reached. Payload stimulus is step 4.", $realtime);
  $finish;
end
