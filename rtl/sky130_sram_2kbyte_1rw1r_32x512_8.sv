`ifdef USE_OPENRAM
(* blackbox *)
module sky130_sram_2kbyte_1rw1r_32x512_8 (
  input logic clk0,
  input logic csb0,
  input logic web0,
  input logic [3:0] wmask0,
  input logic [8:0] addr0,
  input logic [31:0] din0,
  output logic [31:0] dout0,
  input logic clk1,
  input logic csb1,
  input logic [8:0] addr1,
  output logic [31:0] dout1
);
`ifndef SYNTHESIS
  logic [31:0] mem [0:511];
  integer i;

  initial begin
    for (i = 0; i < 512; i = i + 1) mem[i] = 32'd0;
  end

  always_ff @(posedge clk0) begin
    if (!csb0) begin
      if (!web0) begin
        if (wmask0[0]) mem[addr0][7:0] <= din0[7:0];
        if (wmask0[1]) mem[addr0][15:8] <= din0[15:8];
        if (wmask0[2]) mem[addr0][23:16] <= din0[23:16];
        if (wmask0[3]) mem[addr0][31:24] <= din0[31:24];
      end else begin
        dout0 <= mem[addr0];
      end
    end
  end

  always_ff @(posedge clk1) begin
    if (!csb1) begin
      dout1 <= mem[addr1];
    end
  end
`endif
endmodule
`endif
