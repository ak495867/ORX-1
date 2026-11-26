module sram_sp #(
  parameter integer WORDS = 4096,
  parameter integer ADDR_WIDTH = 12
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
  logic read_ack;
  logic is_write;

  assign is_write = |wen;
  assign ack = en && (is_write ? 1'b1 : read_ack);

`ifdef USE_OPENRAM
  localparam integer NUM_BANKS = 8;
  logic [31:0] bank_dout0 [0:NUM_BANKS-1];
  logic [31:0] bank_dout1 [0:NUM_BANKS-1];
  logic [2:0] sel0_q;
  logic [2:0] sel1_q;
  logic [2:0] sel0;
  logic [2:0] sel1;
  genvar b;

  assign sel0 = addr[ADDR_WIDTH-1:ADDR_WIDTH-3];
  assign sel1 = imem_addr[ADDR_WIDTH-1:ADDR_WIDTH-3];
  assign rdata = bank_dout0[sel0_q];
  assign imem_rdata = bank_dout1[sel1_q];
  logic _unused_sram_openram;
  assign _unused_sram_openram = &{1'b0, (WORDS != 0)};

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      sel0_q <= 3'd0;
      sel1_q <= 3'd0;
    end else begin
      if (en && !is_write && !read_ack) sel0_q <= sel0;
      sel1_q <= sel1;
    end
  end

  generate
    for (b = 0; b < NUM_BANKS; b = b + 1) begin : gen_sram_banks
      sky130_sram_2kbyte_1rw1r_32x512_8 u_bank (
        .clk0(clk),
        .csb0(!(en && !read_ack && (sel0 == b[2:0]))),
        .web0(!is_write),
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
`ifndef SYNTHESIS
  integer i;

  initial begin
    for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'd0;
  end
`endif

  assign imem_rdata = mem[imem_addr];

  always_ff @(posedge clk) begin
    if (en) begin
      if (is_write) begin
        if (wen[0]) mem[addr][7:0] <= wdata[7:0];
        if (wen[1]) mem[addr][15:8] <= wdata[15:8];
        if (wen[2]) mem[addr][23:16] <= wdata[23:16];
        if (wen[3]) mem[addr][31:24] <= wdata[31:24];
      end else if (!read_ack) begin
        rdata <= mem[addr];
      end
    end
  end
`endif

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      read_ack <= 1'b0;
    end else begin
      if (en && !is_write && !read_ack) read_ack <= 1'b1;
      else read_ack <= 1'b0;
    end
  end
endmodule
