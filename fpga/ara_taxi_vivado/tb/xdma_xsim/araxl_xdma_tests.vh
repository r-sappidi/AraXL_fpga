else if (testname == "araxl_dotproduct")
begin : araxl_dotproduct_test
  integer k;
  integer payload_len;
  integer loop_timeout;
  integer desc_count;
  integer max_payload_len;
  reg [1023:0] payload_hex;

  payload_len = 0;
  payload_hex = "build/araxl_xdma_payload.hex";
  max_payload_len = 65536 - 1024 - 64;

  if (!$value$plusargs("ARAXL_PAYLOAD_LEN=%d", payload_len)) begin
    $display("---***ERROR*** Missing +ARAXL_PAYLOAD_LEN=<bytes>");
    $finish(2);
  end

  if (!$value$plusargs("ARAXL_PAYLOAD_HEX=%s", payload_hex)) begin
    $display("Using default payload hex: %0s", payload_hex);
  end

  if (payload_len <= 0 || payload_len > max_payload_len) begin
    $display("---***ERROR*** Unsupported payload length %0d. Current XDMA test supports 1..%0d bytes.", payload_len, max_payload_len);
    $finish(2);
  end

  $display("**** AraXL XDMA H2C ELF payload load: %0d bytes from %0s", payload_len, payload_hex);

  for (k = 0; k < payload_len + 64; k = k + 1) begin
    DATA_STORE[1024+k] = 8'h00;
  end
  $readmemh(payload_hex, DATA_STORE, 1024, 1024 + payload_len - 1);

  DATA_STORE[256+0]  = 8'h13;
  DATA_STORE[256+1]  = 8'h00;
  DATA_STORE[256+2]  = 8'h4b;
  DATA_STORE[256+3]  = 8'had;
  DATA_STORE[256+4]  = payload_len[7:0];
  DATA_STORE[256+5]  = payload_len[15:8];
  DATA_STORE[256+6]  = 8'h00;
  DATA_STORE[256+7]  = 8'h00;
  DATA_STORE[256+8]  = 8'h00;
  DATA_STORE[256+9]  = 8'h04;
  DATA_STORE[256+10] = 8'h00;
  DATA_STORE[256+11] = 8'h00;
  DATA_STORE[256+12] = 8'h00;
  DATA_STORE[256+13] = 8'h00;
  DATA_STORE[256+14] = 8'h00;
  DATA_STORE[256+15] = 8'h00;
  DATA_STORE[256+16] = 8'h00;
  DATA_STORE[256+17] = 8'h00;
  DATA_STORE[256+18] = 8'h00;
  DATA_STORE[256+19] = 8'h80;
  DATA_STORE[256+20] = 8'h00;
  DATA_STORE[256+21] = 8'h00;
  DATA_STORE[256+22] = 8'h00;
  DATA_STORE[256+23] = 8'h00;
  DATA_STORE[256+24] = 8'h00;
  DATA_STORE[256+25] = 8'h00;
  DATA_STORE[256+26] = 8'h00;
  DATA_STORE[256+27] = 8'h00;
  DATA_STORE[256+28] = 8'h00;
  DATA_STORE[256+29] = 8'h00;
  DATA_STORE[256+30] = 8'h00;
  DATA_STORE[256+31] = 8'h00;

  board.RP.tx_usrapp.TSK_XDMA_REG_READ(16'h00);
  board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h4080, 32'h00000100, 4'hF);
  board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h0004, 32'h00fffe7f, 4'hF);

  loop_timeout = 0;
  desc_count = 0;
  while (desc_count == 0 && loop_timeout <= 1000) begin
    board.RP.tx_usrapp.TSK_XDMA_REG_READ(16'h0048);
    if (P_READ_DATA == 32'h1) begin
      desc_count = 1;
    end else begin
      #100000;
      loop_timeout = loop_timeout + 1;
    end
  end
  if (desc_count != 1) begin
    $display("---***ERROR*** AraXL payload H2C descriptor did not complete");
    $finish(2);
  end
  board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h0004, 32'h0, 4'hF);

  $display("**** AraXL payload loaded. Releasing core through CTRL core_release register.");

  for (k = 0; k < 16; k = k + 1) begin
    DATA_STORE[1024+k] = 8'h00;
  end
  DATA_STORE[1024] = 8'h01;

  DATA_STORE[256+0]  = 8'h13;
  DATA_STORE[256+1]  = 8'h00;
  DATA_STORE[256+2]  = 8'h4b;
  DATA_STORE[256+3]  = 8'had;
  DATA_STORE[256+4]  = 8'h08;
  DATA_STORE[256+5]  = 8'h00;
  DATA_STORE[256+6]  = 8'h00;
  DATA_STORE[256+7]  = 8'h00;
  DATA_STORE[256+8]  = 8'h00;
  DATA_STORE[256+9]  = 8'h04;
  DATA_STORE[256+10] = 8'h00;
  DATA_STORE[256+11] = 8'h00;
  DATA_STORE[256+12] = 8'h00;
  DATA_STORE[256+13] = 8'h00;
  DATA_STORE[256+14] = 8'h00;
  DATA_STORE[256+15] = 8'h00;
  DATA_STORE[256+16] = 8'h28;
  DATA_STORE[256+17] = 8'h00;
  DATA_STORE[256+18] = 8'h00;
  DATA_STORE[256+19] = 8'hD0;
  DATA_STORE[256+20] = 8'h00;
  DATA_STORE[256+21] = 8'h00;
  DATA_STORE[256+22] = 8'h00;
  DATA_STORE[256+23] = 8'h00;
  DATA_STORE[256+24] = 8'h00;
  DATA_STORE[256+25] = 8'h00;
  DATA_STORE[256+26] = 8'h00;
  DATA_STORE[256+27] = 8'h00;
  DATA_STORE[256+28] = 8'h00;
  DATA_STORE[256+29] = 8'h00;
  DATA_STORE[256+30] = 8'h00;
  DATA_STORE[256+31] = 8'h00;

  board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h4080, 32'h00000100, 4'hF);
  board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h0004, 32'h00fffe7f, 4'hF);

  loop_timeout = 0;
  desc_count = 0;
  while (desc_count == 0 && loop_timeout <= 1000) begin
    board.RP.tx_usrapp.TSK_XDMA_REG_READ(16'h0048);
    if (P_READ_DATA == 32'h1) begin
      desc_count = 1;
    end else begin
      #100000;
      loop_timeout = loop_timeout + 1;
    end
  end
  if (desc_count != 1) begin
    $display("---***ERROR*** AraXL core-release H2C descriptor did not complete");
    $finish(2);
  end
  board.RP.tx_usrapp.TSK_XDMA_REG_WRITE(16'h0004, 32'h0, 4'hF);

  $display("**** AraXL core released. Waiting for program exit register.");
end
