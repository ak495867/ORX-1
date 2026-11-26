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
  output logic [31:0] rdata,
  output logic ack,
  input logic [ADDR_WIDTH-1:0] imem_addr,
  output logic [31:0] imem_rdata
);
  logic [31:0] mem [0:WORDS-1];
  integer i;

  initial begin
    for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'd0;
  end

  assign imem_rdata = mem[imem_addr];

  always_ff @(posedge clk) begin
    if (en && !ack) begin
      if (wen[0]) mem[addr][7:0] <= wdata[7:0];
      if (wen[1]) mem[addr][15:8] <= wdata[15:8];
      if (wen[2]) mem[addr][23:16] <= wdata[23:16];
      if (wen[3]) mem[addr][31:24] <= wdata[31:24];
      rdata <= mem[addr];
    end
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      ack <= 1'b0;
    end else begin
      if (en && !ack) ack <= 1'b1;
      else ack <= 1'b0;
    end
  end
endmodule
