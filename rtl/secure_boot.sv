module secure_boot #(
  parameter logic [2:0] WORDS = 3'd4
) (
  input logic clk,
  input logic reset,
  input logic csr_valid,
  input logic csr_write,
  input logic [7:0] csr_addr,
  input logic [31:0] csr_wdata,
  output logic [31:0] csr_rdata,
  output logic boot_release,
  output logic fail,
  input logic [31:0] boot_word
);
  logic running;
  logic complete;
  logic [31:0] digest;
  logic [31:0] expected_digest;
  logic [31:0] next_digest;
  logic [2:0] boot_index;
  localparam logic [2:0] LAST_INDEX = WORDS - 3'd1;

  assign next_digest = (digest ^ boot_word) * 32'h0100_0193;
  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = {28'd0, fail, boot_release, complete, running};
      8'h04: csr_rdata = digest;
      8'h08: csr_rdata = expected_digest;
      default: csr_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      running <= 1'b0;
      complete <= 1'b0;
      boot_release <= 1'b0;
      fail <= 1'b0;
      digest <= 32'h811c_9dc5;
      expected_digest <= 32'h0000_0000;
      boot_index <= 3'd0;
    end else begin
      if (csr_valid && csr_write) begin
        case (csr_addr)
          8'h00: begin
            if (csr_wdata[0] && !running) begin
              running <= 1'b1;
              complete <= 1'b0;
              boot_release <= 1'b0;
              fail <= 1'b0;
              digest <= 32'h811c_9dc5;
              boot_index <= 3'd0;
            end
          end
          8'h08: expected_digest <= csr_wdata;
          default: begin end
        endcase
      end
      if (running) begin
        digest <= next_digest;
        if (boot_index == LAST_INDEX) begin
          running <= 1'b0;
          complete <= 1'b1;
          if (next_digest == expected_digest) begin
            boot_release <= 1'b1;
            fail <= 1'b0;
          end else begin
            boot_release <= 1'b0;
            fail <= 1'b1;
          end
        end else begin
          boot_index <= boot_index + 3'd1;
        end
      end
    end
  end
endmodule
