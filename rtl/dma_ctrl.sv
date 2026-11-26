module dma_ctrl (
  input logic clk,
  input logic reset,
  input logic csr_valid,
  input logic csr_write,
  input logic [7:0] csr_addr,
  input logic [31:0] csr_wdata,
  output logic [31:0] csr_rdata,
  output logic dma_req_valid,
  input logic dma_req_ready,
  output logic dma_req_write,
  output logic [31:0] dma_req_addr,
  output logic [31:0] dma_req_wdata,
  output logic [3:0] dma_req_wstrb,
  input logic dma_rsp_valid,
  input logic [31:0] dma_rsp_rdata,
  input logic sensor_event,
  output logic dma_irq
);
  typedef enum logic [1:0] {DMA_IDLE, DMA_READ, DMA_WRITE} dma_state_t;
  dma_state_t state;
  logic [31:0] src_addr [0:1];
  logic [31:0] dst_addr [0:1];
  logic [15:0] transfer_len [0:1];
  logic [15:0] cur_count [0:1];
  logic [1:0] ch_busy;
  logic [1:0] ch_done;
  logic [1:0] ch_auto;
  logic [1:0] ch_src_fixed;
  logic [1:0] ch_dst_fixed;
  logic active_ch;
  logic last_ch;
  logic next_ch;
  logic start_ch0;
  logic start_ch1;
  logic [15:0] next_cnt;
  logic [31:0] cur_dst_addr;
  logic [31:0] next_src_addr;

  assign dma_req_wstrb = 4'b1111;
  assign cur_dst_addr = ch_dst_fixed[active_ch] ? dst_addr[active_ch] : (dst_addr[active_ch] + ({16'd0, cur_count[active_ch]} << 2));
  assign next_cnt = cur_count[active_ch] + 16'd1;
  assign next_src_addr = ch_src_fixed[active_ch] ? src_addr[active_ch] : (src_addr[active_ch] + ({16'd0, next_cnt} << 2));

  always_comb begin
    start_ch0 = ch_busy[0] || (ch_auto[0] && sensor_event && transfer_len[0] != 16'd0);
    start_ch1 = ch_busy[1] || (ch_auto[1] && sensor_event && transfer_len[1] != 16'd0);
    if (last_ch == 1'b0) begin
      next_ch = start_ch1 ? 1'b1 : 1'b0;
    end else begin
      next_ch = start_ch0 ? 1'b0 : 1'b1;
    end

    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = src_addr[0];
      8'h04: csr_rdata = dst_addr[0];
      8'h08: csr_rdata = {16'd0, transfer_len[0]};
      8'h0c: csr_rdata = {26'd0, ch_dst_fixed[0], ch_src_fixed[0], ch_auto[0], ch_done[0], ch_busy[0], 1'b0};
      8'h10: csr_rdata = src_addr[1];
      8'h14: csr_rdata = dst_addr[1];
      8'h18: csr_rdata = {16'd0, transfer_len[1]};
      8'h1c: csr_rdata = {26'd0, ch_dst_fixed[1], ch_src_fixed[1], ch_auto[1], ch_done[1], ch_busy[1], 1'b0};
      default: csr_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      state <= DMA_IDLE;
      src_addr[0] <= 32'd0;
      src_addr[1] <= 32'd0;
      dst_addr[0] <= 32'd0;
      dst_addr[1] <= 32'd0;
      transfer_len[0] <= 16'd0;
      transfer_len[1] <= 16'd0;
      cur_count[0] <= 16'd0;
      cur_count[1] <= 16'd0;
      ch_busy <= 2'b00;
      ch_done <= 2'b00;
      ch_auto <= 2'b00;
      ch_src_fixed <= 2'b00;
      ch_dst_fixed <= 2'b00;
      active_ch <= 1'b0;
      last_ch <= 1'b1;
      dma_req_valid <= 1'b0;
      dma_req_write <= 1'b0;
      dma_req_addr <= 32'd0;
      dma_req_wdata <= 32'd0;
      dma_irq <= 1'b0;
    end else begin
      dma_irq <= 1'b0;

      if (ch_auto[0] && sensor_event && !ch_busy[0] && transfer_len[0] != 16'd0) begin
        ch_busy[0] <= 1'b1;
        ch_done[0] <= 1'b0;
        cur_count[0] <= 16'd0;
      end
      if (ch_auto[1] && sensor_event && !ch_busy[1] && transfer_len[1] != 16'd0) begin
        ch_busy[1] <= 1'b1;
        ch_done[1] <= 1'b0;
        cur_count[1] <= 16'd0;
      end

      if (csr_valid && csr_write) begin
        case (csr_addr)
          8'h00: src_addr[0] <= csr_wdata;
          8'h04: dst_addr[0] <= csr_wdata;
          8'h08: transfer_len[0] <= csr_wdata[15:0];
          8'h0c: begin
            ch_auto[0] <= csr_wdata[3];
            ch_src_fixed[0] <= csr_wdata[4];
            ch_dst_fixed[0] <= csr_wdata[5];
            if (csr_wdata[1]) ch_done[0] <= 1'b0;
            if (csr_wdata[0] && !ch_busy[0] && transfer_len[0] != 16'd0) begin
              ch_busy[0] <= 1'b1;
              ch_done[0] <= 1'b0;
              cur_count[0] <= 16'd0;
            end
          end
          8'h10: src_addr[1] <= csr_wdata;
          8'h14: dst_addr[1] <= csr_wdata;
          8'h18: transfer_len[1] <= csr_wdata[15:0];
          8'h1c: begin
            ch_auto[1] <= csr_wdata[3];
            ch_src_fixed[1] <= csr_wdata[4];
            ch_dst_fixed[1] <= csr_wdata[5];
            if (csr_wdata[1]) ch_done[1] <= 1'b0;
            if (csr_wdata[0] && !ch_busy[1] && transfer_len[1] != 16'd0) begin
              ch_busy[1] <= 1'b1;
              ch_done[1] <= 1'b0;
              cur_count[1] <= 16'd0;
            end
          end
          default: begin end
        endcase
      end

      case (state)
        DMA_IDLE: begin
          if (ch_busy[0] || ch_busy[1]) begin
            active_ch <= next_ch;
            dma_req_valid <= 1'b1;
            dma_req_write <= 1'b0;
            dma_req_addr <= ch_src_fixed[next_ch] ? src_addr[next_ch] : (src_addr[next_ch] + ({16'd0, cur_count[next_ch]} << 2));
            state <= DMA_READ;
          end else begin
            dma_req_valid <= 1'b0;
          end
        end
        DMA_READ: begin
          if (dma_req_ready && dma_rsp_valid) begin
            dma_req_valid <= 1'b1;
            dma_req_write <= 1'b1;
            dma_req_addr <= cur_dst_addr;
            dma_req_wdata <= dma_rsp_rdata;
            state <= DMA_WRITE;
          end
        end
        DMA_WRITE: begin
          if (dma_req_ready) begin
            last_ch <= active_ch;
            if (next_cnt >= transfer_len[active_ch]) begin
              dma_req_valid <= 1'b0;
              ch_busy[active_ch] <= 1'b0;
              ch_done[active_ch] <= 1'b1;
              dma_irq <= 1'b1;
              state <= DMA_IDLE;
            end else if (ch_busy[!active_ch]) begin
              cur_count[active_ch] <= next_cnt;
              dma_req_valid <= 1'b0;
              state <= DMA_IDLE;
            end else begin
              cur_count[active_ch] <= next_cnt;
              dma_req_valid <= 1'b1;
              dma_req_write <= 1'b0;
              dma_req_addr <= next_src_addr;
              state <= DMA_READ;
            end
          end
        end
        default: state <= DMA_IDLE;
      endcase
    end
  end
endmodule
