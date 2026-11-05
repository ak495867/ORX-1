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
  logic [31:0] src_addr;
  logic [31:0] dst_addr;
  logic [15:0] transfer_len;
  logic [15:0] cur_count;
  logic [31:0] hold_data;
  logic ch_busy;
  logic ch_done;
  logic ch_auto;

  assign dma_req_wstrb = 4'b1111;

  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = src_addr;
      8'h04: csr_rdata = dst_addr;
      8'h08: csr_rdata = {16'd0, transfer_len};
      8'h0c: csr_rdata = {28'd0, ch_auto, ch_done, ch_busy, 1'b0};
      default: csr_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      state <= DMA_IDLE;
      src_addr <= 32'd0;
      dst_addr <= 32'd0;
      transfer_len <= 16'd0;
      cur_count <= 16'd0;
      hold_data <= 32'd0;
      ch_busy <= 1'b0;
      ch_done <= 1'b0;
      ch_auto <= 1'b0;
      dma_req_valid <= 1'b0;
      dma_req_write <= 1'b0;
      dma_req_addr <= 32'd0;
      dma_req_wdata <= 32'd0;
      dma_irq <= 1'b0;
    end else begin
      dma_irq <= 1'b0;
      if (csr_valid && csr_write) begin
        case (csr_addr)
          8'h00: src_addr <= csr_wdata;
          8'h04: dst_addr <= csr_wdata;
          8'h08: transfer_len <= csr_wdata[15:0];
          8'h0c: begin
            ch_auto <= csr_wdata[3];
            if (csr_wdata[1]) ch_done <= 1'b0;
            if (csr_wdata[0] && !ch_busy && transfer_len != 16'd0) begin
              ch_busy <= 1'b1;
              ch_done <= 1'b0;
              cur_count <= 16'd0;
              dma_req_valid <= 1'b1;
              dma_req_write <= 1'b0;
              dma_req_addr <= src_addr;
              state <= DMA_READ;
            end
          end
          default: begin end
        endcase
      end else if (ch_auto && sensor_event && !ch_busy && transfer_len != 16'd0) begin
        ch_busy <= 1'b1;
        ch_done <= 1'b0;
        cur_count <= 16'd0;
        dma_req_valid <= 1'b1;
        dma_req_write <= 1'b0;
        dma_req_addr <= src_addr;
        state <= DMA_READ;
      end

      case (state)
        DMA_READ: begin
          if (dma_req_ready && dma_rsp_valid) begin
            hold_data <= dma_rsp_rdata;
            dma_req_valid <= 1'b1;
            dma_req_write <= 1'b1;
            dma_req_addr <= dst_addr + (cur_count << 2);
            dma_req_wdata <= dma_rsp_rdata;
            state <= DMA_WRITE;
          end
        end
        DMA_WRITE: begin
          if (dma_req_ready) begin
            if (cur_count + 16'd1 >= transfer_len) begin
              dma_req_valid <= 1'b0;
              ch_busy <= 1'b0;
              ch_done <= 1'b1;
              dma_irq <= 1'b1;
              state <= DMA_IDLE;
            end else begin
              cur_count <= cur_count + 16'd1;
              dma_req_valid <= 1'b1;
              dma_req_write <= 1'b0;
              dma_req_addr <= src_addr + ((cur_count + 16'd1) << 2);
              state <= DMA_READ;
            end
          end
        end
        default: state <= DMA_IDLE;
      endcase
    end
  end
endmodule
