module secure_boot #(
  parameter integer WORDS = 4
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
  output logic [7:0] boot_addr,
  output logic [2:0] boot_addr_hi,
  output logic src_sram,
  output logic sram_rd_active,
  input logic [31:0] boot_word
);
  typedef enum logic [1:0] {SB_IDLE, SB_LOAD, SB_HASH} sb_state_t;
  sb_state_t sb_state;
  logic running;
  logic complete;
  logic [31:0] digest;
  logic [31:0] expected_digest;
  logic [31:0] next_digest;
  logic [11:0] image_words;
  logic [11:0] boot_index;
  logic [3:0] block_word_idx;
  logic first_block;
  logic final_block;
  logic pad_pending;
  logic need_80_in_pad;

  logic mode_sha256;
  logic efuse_lock;
  logic sha_init;
  logic sha_start;
  logic sha_done;
  logic [255:0] sha_digest;
  logic [31:0] sha_block [0:15];
  logic [2:0] efuse_idx;
  logic [31:0] efuse_hash [0:7];
  logic [511:0] sha_block_flat;
  logic [31:0] msg_bit_len;
  integer i;

  assign running = (sb_state != SB_IDLE);
  assign boot_addr = boot_index[7:0];
  assign boot_addr_hi = boot_index[10:8];
  assign sram_rd_active = src_sram && (sb_state == SB_LOAD);
  assign next_digest = (digest ^ boot_word) * 32'h0100_0193;
  assign msg_bit_len = {15'd0, image_words, 5'd0};

  assign sha_block_flat = {
    sha_block[15], sha_block[14], sha_block[13], sha_block[12],
    sha_block[11], sha_block[10], sha_block[9],  sha_block[8],
    sha_block[7],  sha_block[6],  sha_block[5],  sha_block[4],
    sha_block[3],  sha_block[2],  sha_block[1],  sha_block[0]
  };

  sha256_engine u_sha256 (
    .clk(clk),
    .reset(reset),
    .init(sha_init),
    .start(sha_start),
    .block_data(sha_block_flat),
    .done(sha_done),
    .digest(sha_digest)
  );

  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = {24'd0, src_sram, 1'b0, efuse_lock, mode_sha256, fail, boot_release, complete, running};
      8'h04: csr_rdata = mode_sha256 ? sha_digest[31:0] : digest;
      8'h08: csr_rdata = expected_digest;
      8'h0c: csr_rdata = {29'd0, efuse_idx};
      8'h10: csr_rdata = efuse_hash[efuse_idx];
      8'h14: csr_rdata = {20'd0, image_words};
      8'h18: begin
        case (efuse_idx)
          3'd0: csr_rdata = sha_digest[31:0];
          3'd1: csr_rdata = sha_digest[63:32];
          3'd2: csr_rdata = sha_digest[95:64];
          3'd3: csr_rdata = sha_digest[127:96];
          3'd4: csr_rdata = sha_digest[159:128];
          3'd5: csr_rdata = sha_digest[191:160];
          3'd6: csr_rdata = sha_digest[223:192];
          default: csr_rdata = sha_digest[255:224];
        endcase
      end
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
      image_words <= WORDS[11:0];
      boot_index <= 12'd0;
      block_word_idx <= 4'd0;
      first_block <= 1'b1;
      final_block <= 1'b0;
      pad_pending <= 1'b0;
      need_80_in_pad <= 1'b0;
      mode_sha256 <= 1'b0;
      src_sram <= 1'b0;
      efuse_lock <= 1'b0;
      sha_init <= 1'b0;
      sha_start <= 1'b0;
      efuse_idx <= 3'd0;
      for (i = 0; i < 8; i = i + 1) efuse_hash[i] <= 32'd0;
      for (i = 0; i < 16; i = i + 1) sha_block[i] <= 32'd0;
    end else begin
      sha_init <= 1'b0;
      sha_start <= 1'b0;
      if (csr_valid && csr_write) begin
        case (csr_addr)
          8'h00: begin
            if (csr_wdata[1]) complete <= 1'b0;
            if (csr_wdata[6]) efuse_lock <= 1'b1;
            if (sb_state == SB_IDLE) begin
              mode_sha256 <= csr_wdata[5];
              src_sram <= csr_wdata[7];
              if (csr_wdata[0]) begin
                sb_state <= SB_LOAD;
                complete <= 1'b0;
                boot_release <= 1'b0;
                fail <= 1'b0;
                digest <= 32'h811c_9dc5;
                boot_index <= 12'd0;
                block_word_idx <= 4'd0;
                first_block <= 1'b1;
                final_block <= 1'b0;
                pad_pending <= 1'b0;
                need_80_in_pad <= 1'b0;
                for (i = 0; i < 16; i = i + 1) sha_block[i] <= 32'd0;
              end
            end
          end
          8'h08: expected_digest <= csr_wdata;
          8'h0c: efuse_idx <= csr_wdata[2:0];
          8'h10: begin
            if (!efuse_lock) efuse_hash[efuse_idx] <= csr_wdata;
          end
          8'h14: begin
            if (sb_state == SB_IDLE && csr_wdata != 32'd0 && csr_wdata <= 32'd2048) begin
              image_words <= csr_wdata[11:0];
            end
          end
          default: begin end
        endcase
      end
      case (sb_state)
        SB_LOAD: begin
          digest <= next_digest;
          sha_block[block_word_idx] <= boot_word;
          if (boot_index + 12'd1 == image_words) begin
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
              sha_init <= first_block;
              sha_start <= 1'b1;
              sb_state <= SB_HASH;
              if (block_word_idx <= 4'd13) begin
                sha_block[block_word_idx + 4'd1] <= 32'h8000_0000;
                sha_block[15] <= msg_bit_len;
                final_block <= 1'b1;
                pad_pending <= 1'b0;
              end else if (block_word_idx == 4'd14) begin
                sha_block[15] <= 32'h8000_0000;
                final_block <= 1'b0;
                pad_pending <= 1'b1;
                need_80_in_pad <= 1'b0;
              end else begin
                final_block <= 1'b0;
                pad_pending <= 1'b1;
                need_80_in_pad <= 1'b1;
              end
            end
          end else begin
            boot_index <= boot_index + 12'd1;
            if (mode_sha256 && block_word_idx == 4'd15) begin
              sha_init <= first_block;
              sha_start <= 1'b1;
              final_block <= 1'b0;
              pad_pending <= 1'b0;
              sb_state <= SB_HASH;
            end else begin
              block_word_idx <= block_word_idx + 4'd1;
            end
          end
        end
        SB_HASH: begin
          if (sha_done) begin
            first_block <= 1'b0;
            for (i = 0; i < 16; i = i + 1) sha_block[i] <= 32'd0;
            if (final_block) begin
              sb_state <= SB_IDLE;
              complete <= 1'b1;
              if (sha_digest == {efuse_hash[7], efuse_hash[6], efuse_hash[5], efuse_hash[4], efuse_hash[3], efuse_hash[2], efuse_hash[1], efuse_hash[0]}) begin
                boot_release <= 1'b1;
                fail <= 1'b0;
              end else begin
                boot_release <= 1'b0;
                fail <= 1'b1;
              end
            end else if (pad_pending) begin
              if (need_80_in_pad) sha_block[0] <= 32'h8000_0000;
              sha_block[15] <= msg_bit_len;
              sha_start <= 1'b1;
              final_block <= 1'b1;
              pad_pending <= 1'b0;
            end else begin
              block_word_idx <= 4'd0;
              sb_state <= SB_LOAD;
            end
          end
        end
        default: begin end
      endcase
    end
  end
endmodule
