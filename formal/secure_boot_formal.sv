module secure_boot_formal (
  input logic clk,
  input logic reset,
  input logic csr_valid,
  input logic csr_write,
  input logic [7:0] csr_addr,
  input logic [31:0] csr_wdata,
  input logic [31:0] boot_word
);
  logic [31:0] csr_rdata;
  logic boot_release;
  logic fail;
  logic [7:0] boot_addr;
  logic [2:0] boot_addr_hi;
  logic src_sram;
  logic sram_rd_active;
  logic past_valid;

  secure_boot dut (
    .clk(clk), .reset(reset),
    .csr_valid(csr_valid), .csr_write(csr_write), .csr_addr(csr_addr), .csr_wdata(csr_wdata),
    .csr_rdata(csr_rdata),
    .boot_release(boot_release), .fail(fail),
    .boot_addr(boot_addr), .boot_addr_hi(boot_addr_hi),
    .src_sram(src_sram), .sram_rd_active(sram_rd_active),
    .boot_word(boot_word)
  );

  initial begin
    past_valid = 1'b0;
  end

  always @(posedge clk) begin
    past_valid <= 1'b1;
    if (!past_valid) begin
      assume (reset);
    end

    if (past_valid && !reset && $past(!reset)) begin
      assert (!(boot_release && fail));
      assert (!sram_rd_active || src_sram);
      if (csr_addr == 8'h00) begin
        assert (!(csr_rdata[0] && (boot_release || fail)));
        assert (!sram_rd_active || csr_rdata[0]);
      end
      if ($past(csr_addr == 8'h00 && csr_rdata[5]) && csr_addr == 8'h00) begin
        assert (csr_rdata[5]);
      end
    end
  end
endmodule
