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

  logic [7:0] tx_data;
  logic [7:0] tx_shift;
  logic [2:0] tx_bit_index;
  logic tx_busy;
  logic tx_done;

  logic [7:0] rx_data;
  logic [7:0] rx_shift;
  logic [2:0] rx_bit_index;
  logic rx_valid;
  logic rx_overrun;
  logic rx_sync_0, rx_sync_1;

  assign uart_irq = rx_valid | tx_done;

  always_comb begin
    csr_rdata = 32'd0;
    case (csr_addr)
      8'h00: csr_rdata = {24'd0, rx_data};
      8'h04: csr_rdata = {28'd0, rx_overrun, rx_valid, tx_done, tx_busy};
      8'h08: csr_rdata = {16'd0, baud_div};
      default: csr_rdata = 32'd0;
    endcase
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      tx_state <= TX_IDLE;
      rx_state <= RX_IDLE;
      baud_div <= 16'd16;
      tx_div_count <= 16'd0;
      rx_div_count <= 16'd0;
      tx_data <= 8'd0;
      tx_shift <= 8'd0;
      tx_bit_index <= 3'd0;
      tx_busy <= 1'b0;
      tx_done <= 1'b0;
      tx <= 1'b1;
      rx_data <= 8'd0;
      rx_shift <= 8'd0;
      rx_bit_index <= 3'd0;
      rx_valid <= 1'b0;
      rx_overrun <= 1'b0;
      rx_sync_0 <= 1'b1;
      rx_sync_1 <= 1'b1;
    end else begin
      rx_sync_0 <= rx;
      rx_sync_1 <= rx_sync_0;

      if (csr_valid && csr_write) begin
        case (csr_addr)
          8'h00: begin
            if (!tx_busy) begin
              tx_data <= csr_wdata[7:0];
              tx_shift <= csr_wdata[7:0];
              tx_div_count <= 16'd0;
              tx_bit_index <= 3'd0;
              tx_busy <= 1'b1;
              tx_done <= 1'b0;
              tx <= 1'b0;
              tx_state <= TX_START;
            end
          end
          8'h08: baud_div <= csr_wdata[15:0];
          8'h0c: begin
            if (csr_wdata[0]) rx_valid <= 1'b0;
            if (csr_wdata[1]) rx_overrun <= 1'b0;
          end
          default: begin end
        endcase
      end

      case (tx_state)
        TX_IDLE: begin
          tx <= 1'b1;
          tx_busy <= 1'b0;
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
            tx_done <= 1'b1;
            tx_state <= TX_IDLE;
          end else begin
            tx_div_count <= tx_div_count + 16'd1;
          end
        end
        default: tx_state <= TX_IDLE;
      endcase

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
            if (rx_sync_1) begin
              if (rx_valid) rx_overrun <= 1'b1;
              rx_data <= rx_shift;
              rx_valid <= 1'b1;
            end
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
