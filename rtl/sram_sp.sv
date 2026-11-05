module sram_sp #(
  parameter integer WORDS = 1024,
  parameter integer ADDR_WIDTH = 10
) (
  input logic clk,
  input logic reset,
  input logic en,
  input logic [3:0] wen,
  input logic [ADDR_WIDTH-1:0] addr,
  input logic [31:0] wdata,
  output logic [31:0] rdata
);
  logic [31:0] mem [0:WORDS-1];

  always_ff @(posedge clk) begin
    if (en) begin
      if (wen[0]) mem[addr][7:0] <= wdata[7:0];
      if (wen[1]) mem[addr][15:8] <= wdata[15:8];
      if (wen[2]) mem[addr][23:16] <= wdata[23:16];
      if (wen[3]) mem[addr][31:24] <= wdata[31:24];
      rdata <= mem[addr];
    end
  end
endmodule
