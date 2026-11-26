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
  output logic [2:0] boot_addr,
  input logic [31:0] boot_word
);
  typedef enum logic [1:0] {SB_IDLE, SB_LOAD, SB_HASH} sb_state_t;
  sb_state_t sb_state;
  logic running;
  logic complete;
  logic [31:0] digest;
  logic [31:0] expected_digest;
  logic [31:0] next_digest;
  logic [2:0] boot_index;
  localparam logic [2:0] LAST_INDEX = WORDS - 3'd1;

  logic mode_sha256;
  logic sha_start;
  logic sha_done;
  logic [255:0] sha_digest;
  logic [31:0] sha_block [0:15];
  logic [2:0] efuse_idx;
  logic [31:0] efuse_hash [0:7];
  logic [511:0] sha_block_flat;
  integer i;

  assign running = (sb_state != SB_IDLE);

  assign sha_block_flat = {
    sha_block[15], sha_block[14], sha_block[13], sha_block[12],
    sha_block[11], sha_block[10], sha_block[9],  sha_block[8],
    sha_block[7],  sha_block[6],  sha_block[5],  sha_block[4],
    sha_block[3],  sha_block[2],  sha_block[1],  sha_block[0]
  };

  sha256_engine u_sha256 (
    .clk(clk),
    .reset(reset),
    .init(1'b0),
    .start(sha_start),
    .block_data(sha_block_flat),
    .done(sha_done),
    .digest(sha_digest)
  );

  assign boot_addr = boot_index;
  assign next_digest = (digest ^ boot_word) * 32'h0100_0193;

  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = {26'd0, mode_sha256, fail, boot_release, complete, running};
      8'h04: csr_rdata = mode_sha256 ? sha_digest[31:0] : digest;
      8'h08: csr_rdata = expected_digest;
      8'h0c: csr_rdata = {29'd0, efuse_idx};
      8'h10: csr_rdata = efuse_hash[efuse_idx];
      default: csr_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      sb_state <= SB_IDLE;
      complete <= 1'b0;
      boot_release <= 1'b0;
      fail <= 1'b0;
      digest <= 32'h811c_9dc5;
      expected_digest <= 32'h0000_0000;
      boot_index <= 3'd0;
      mode_sha256 <= 1'b0;
      sha_start <= 1'b0;
      efuse_idx <= 3'd0;
      for (i = 0; i < 8; i = i + 1) efuse_hash[i] <= 32'd0;
      for (i = 0; i < 16; i = i + 1) sha_block[i] <= 32'd0;
    end else begin
      sha_start <= 1'b0;
      if (csr_valid && csr_write) begin
        case (csr_addr)
          8'h00: begin
            if (csr_wdata[1]) complete <= 1'b0;
            if (sb_state == SB_IDLE) begin
              mode_sha256 <= csr_wdata[5];
              if (csr_wdata[0]) begin
                sb_state <= SB_LOAD;
                complete <= 1'b0;
                boot_release <= 1'b0;
                fail <= 1'b0;
                digest <= 32'h811c_9dc5;
                boot_index <= 3'd0;
                for (i = 0; i < 16; i = i + 1) sha_block[i] <= 32'd0;
              end
            end
          end
          8'h08: expected_digest <= csr_wdata;
          8'h0c: efuse_idx <= csr_wdata[2:0];
          8'h10: efuse_hash[efuse_idx] <= csr_wdata;
          default: begin end
        endcase
      end
      case (sb_state)
        SB_LOAD: begin
          digest <= next_digest;
          sha_block[{1'b0, boot_index}] <= boot_word;
          if (boot_index == LAST_INDEX) begin
            if (!mode_sha256) begin
              sb_state <= SB_IDLE;
              complete <= 1'b1;
              if (next_digest == expected_digest) begin
                boot_release <= 1'b1;
                fail <= 1'b0;
              end else begin
                boot_release <= 1'b0;
                fail <= 1'b1;
              end
            end else begin
              sha_block[{1'b0, WORDS}] <= 32'h8000_0000;
              sha_block[15] <= {24'd0, WORDS, 5'd0};
              sha_start <= 1'b1;
              sb_state <= SB_HASH;
            end
          end else begin
            boot_index <= boot_index + 3'd1;
          end
        end
        SB_HASH: begin
          if (sha_done) begin
            sb_state <= SB_IDLE;
            complete <= 1'b1;
            if (sha_digest == {efuse_hash[7], efuse_hash[6], efuse_hash[5], efuse_hash[4], efuse_hash[3], efuse_hash[2], efuse_hash[1], efuse_hash[0]}) begin
              boot_release <= 1'b1;
              fail <= 1'b0;
            end else begin
              boot_release <= 1'b0;
              fail <= 1'b1;
            end
          end
        end
        default: begin end
      endcase
    end
  end
endmodule
