module sram_sp #(
  parameter integer WORDS = 2048,
  parameter integer ADDR_WIDTH = 11
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
`ifdef USE_OPENRAM
  logic [31:0] bank_dout0 [0:3];
  logic [31:0] bank_dout1 [0:3];
  logic [1:0] sel0;
  logic [1:0] sel1;
  genvar b;

  assign sel0 = addr[ADDR_WIDTH-1:ADDR_WIDTH-2];
  assign sel1 = imem_addr[ADDR_WIDTH-1:ADDR_WIDTH-2];
  assign rdata = bank_dout0[sel0];
  assign imem_rdata = bank_dout1[sel1];

  generate
    for (b = 0; b < 4; b = b + 1) begin : gen_sram_banks
      sky130_sram_2kbyte_1rw1r_32x512_8 u_bank (
        .clk0(clk),
        .csb0(!(en && !ack && (sel0 == b[1:0]))),
        .web0(!(|wen)),
        .wmask0(wen),
        .addr0(addr[8:0]),
        .din0(wdata),
        .dout0(bank_dout0[b]),
        .clk1(clk),
        .csb1(1'b0),
        .addr1(imem_addr[8:0]),
        .dout1(bank_dout1[b])
      );
    end
  endgenerate
`else
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
`endif

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      ack <= 1'b0;
    end else begin
      if (en && !ack) ack <= 1'b1;
      else ack <= 1'b0;
    end
  end
endmodule
