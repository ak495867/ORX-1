module uart_core (
  input logic clk,
  input logic reset,
  input logic csr_valid,
  input logic csr_write,
  input logic [7:0] csr_addr,
  input logic [31:0] csr_wdata,
  output logic [31:0] csr_rdata,
  input logic rx,
  output logic tx,
  output logic uart_irq
);
  typedef enum logic [1:0] {TX_IDLE, TX_START, TX_DATA, TX_STOP} tx_state_t;
  typedef enum logic [1:0] {RX_IDLE, RX_START, RX_DATA, RX_STOP} rx_state_t;

  tx_state_t tx_state;
  rx_state_t rx_state;

  logic [15:0] baud_div;
  logic [15:0] tx_div_count;
  logic [15:0] rx_div_count;

  logic [7:0] tx_fifo [0:7];
  logic [2:0] tx_head;
  logic [2:0] tx_tail;
  logic [3:0] tx_count;
  logic [7:0] tx_shift;
  logic [2:0] tx_bit_index;
  logic tx_busy;
  logic tx_done;
  logic tx_full;
  logic tx_empty;

  logic [7:0] rx_fifo [0:7];
  logic [2:0] rx_head;
  logic [2:0] rx_tail;
  logic [3:0] rx_count;
  logic [7:0] rx_last_data;
  logic [7:0] rx_shift;
  logic [2:0] rx_bit_index;
  logic rx_valid;
  logic rx_overrun;
  logic rx_full;
  logic rx_sync_0, rx_sync_1;
  logic rx_irq_en;
  logic tx_irq_en;

  logic tx_push;
  logic tx_pop;
  logic rx_push;
  logic rx_pop;
  logic rx_flush;
  logic _unused_wdata;

  assign _unused_wdata = &{1'b0, csr_wdata[31:16]};

  assign tx_full = (tx_count == 4'd8);
  assign tx_empty = (tx_count == 4'd0);
  assign rx_full = (rx_count == 4'd8);
  assign rx_valid = (rx_count != 4'd0);
  assign uart_irq = (rx_valid & rx_irq_en) | (tx_done & tx_irq_en);

  assign tx_push = csr_valid && csr_write && (csr_addr == 8'h00) && !tx_full;
  assign tx_pop = (tx_state == TX_IDLE) && (tx_count != 4'd0);
  assign rx_pop = csr_valid && !csr_write && (csr_addr == 8'h00) && (rx_count != 4'd0);
  assign rx_flush = csr_valid && csr_write && (csr_addr == 8'h0c) && csr_wdata[0];
  assign rx_push = (rx_state == RX_STOP) && (rx_div_count >= baud_div) && rx_sync_1;

  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = {24'd0, (rx_count != 4'd0) ? rx_fifo[rx_head] : rx_last_data};
      8'h04: csr_rdata = {25'd0, rx_full, tx_empty, tx_busy, rx_overrun, rx_valid, tx_done, tx_full};
      8'h08: csr_rdata = {16'd0, baud_div};
      8'h10: csr_rdata = {30'd0, tx_irq_en, rx_irq_en};
      default: csr_rdata = 32'd0;
    endcase
  end

  integer idx;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      tx_state <= TX_IDLE;
      rx_state <= RX_IDLE;
      baud_div <= 16'd16;
      tx_div_count <= 16'd0;
      rx_div_count <= 16'd0;
      tx_head <= 3'd0;
      tx_tail <= 3'd0;
      tx_count <= 4'd0;
      tx_shift <= 8'd0;
      tx_bit_index <= 3'd0;
      tx_busy <= 1'b0;
      tx_done <= 1'b0;
      tx <= 1'b1;
      rx_head <= 3'd0;
      rx_tail <= 3'd0;
      rx_count <= 4'd0;
      rx_last_data <= 8'd0;
      rx_shift <= 8'd0;
      rx_bit_index <= 3'd0;
      rx_overrun <= 1'b0;
      rx_sync_0 <= 1'b1;
      rx_sync_1 <= 1'b1;
      rx_irq_en <= 1'b0;
      tx_irq_en <= 1'b0;
      for (idx = 0; idx < 8; idx = idx + 1) begin
        tx_fifo[idx] <= 8'd0;
        rx_fifo[idx] <= 8'd0;
      end
    end else begin
      rx_sync_0 <= rx;
      rx_sync_1 <= rx_sync_0;

      if (tx_push) begin
        tx_fifo[tx_tail] <= csr_wdata[7:0];
        tx_tail <= tx_tail + 3'd1;
        tx_done <= 1'b0;
      end
      if (tx_pop) begin
        tx_head <= tx_head + 3'd1;
      end
      if (tx_push && !tx_pop) tx_count <= tx_count + 4'd1;
      else if (!tx_push && tx_pop) tx_count <= tx_count - 4'd1;

      if (rx_flush) begin
        rx_head <= 3'd0;
        rx_tail <= 3'd0;
        rx_count <= 4'd0;
      end else begin
        if (rx_push) begin
          if (!rx_full || rx_pop) begin
            rx_fifo[rx_tail] <= rx_shift;
            rx_tail <= rx_tail + 3'd1;
          end else begin
            rx_overrun <= 1'b1;
          end
        end
        if (rx_pop) begin
          rx_last_data <= rx_fifo[rx_head];
          rx_head <= rx_head + 3'd1;
        end
        if (rx_push && !rx_full && !rx_pop) rx_count <= rx_count + 4'd1;
        else if ((!rx_push || rx_full) && rx_pop) rx_count <= rx_count - 4'd1;
      end

      case (tx_state)
        TX_IDLE: begin
          if (tx_count != 4'd0) begin
            tx_shift <= tx_fifo[tx_head];
            tx_div_count <= 16'd0;
            tx_bit_index <= 3'd0;
            tx_busy <= 1'b1;
            tx_done <= 1'b0;
            tx <= 1'b0;
            tx_state <= TX_START;
          end else begin
            tx <= 1'b1;
            tx_busy <= 1'b0;
          end
        end
        TX_START: begin
          tx <= 1'b0;
          if (tx_div_count >= baud_div) begin
            tx_div_count <= 16'd0;
            tx <= tx_shift[0];
            tx_state <= TX_DATA;
          end else begin
            tx_div_count <= tx_div_count + 16'd1;
          end
        end
        TX_DATA: begin
          tx <= tx_shift[0];
          if (tx_div_count >= baud_div) begin
            tx_div_count <= 16'd0;
            if (tx_bit_index == 3'd7) begin
              tx <= 1'b1;
              tx_state <= TX_STOP;
            end else begin
              tx_bit_index <= tx_bit_index + 3'd1;
              tx_shift <= {1'b0, tx_shift[7:1]};
              tx <= tx_shift[1];
            end
          end else begin
            tx_div_count <= tx_div_count + 16'd1;
          end
        end
        TX_STOP: begin
          tx <= 1'b1;
          if (tx_div_count >= baud_div) begin
            tx_div_count <= 16'd0;
            tx_busy <= 1'b0;
            if (tx_count == 4'd0) tx_done <= 1'b1;
            tx_state <= TX_IDLE;
          end else begin
            tx_div_count <= tx_div_count + 16'd1;
          end
        end
        default: tx_state <= TX_IDLE;
      endcase

      if (csr_valid && csr_write) begin
        case (csr_addr)
          8'h08: baud_div <= csr_wdata[15:0];
          8'h0c: begin
            if (csr_wdata[1]) rx_overrun <= 1'b0;
            if (csr_wdata[2]) tx_done <= 1'b0;
          end
          8'h10: begin
            rx_irq_en <= csr_wdata[0];
            tx_irq_en <= csr_wdata[1];
          end
          default: begin end
        endcase
      end

      case (rx_state)
        RX_IDLE: begin
          if (!rx_sync_1) begin
            rx_div_count <= 16'd0;
            rx_state <= RX_START;
          end
        end
        RX_START: begin
          if (rx_div_count >= (baud_div >> 1)) begin
            if (!rx_sync_1) begin
              rx_div_count <= 16'd0;
              rx_bit_index <= 3'd0;
              rx_state <= RX_DATA;
            end else begin
              rx_state <= RX_IDLE;
            end
          end else begin
            rx_div_count <= rx_div_count + 16'd1;
          end
        end
        RX_DATA: begin
          if (rx_div_count >= baud_div) begin
            rx_div_count <= 16'd0;
            rx_shift <= {rx_sync_1, rx_shift[7:1]};
            if (rx_bit_index == 3'd7) begin
              rx_state <= RX_STOP;
            end else begin
              rx_bit_index <= rx_bit_index + 3'd1;
            end
          end else begin
            rx_div_count <= rx_div_count + 16'd1;
          end
        end
        RX_STOP: begin
          if (rx_div_count >= baud_div) begin
            rx_div_count <= 16'd0;
            rx_state <= RX_IDLE;
          end else begin
            rx_div_count <= rx_div_count + 16'd1;
          end
        end
        default: rx_state <= RX_IDLE;
      endcase
    end
  end
endmodule
